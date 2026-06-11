#!/usr/bin/env ruby
# frozen_string_literal: true

# =============================================================================
# tool/audit/audit.rb
#
# Dependency security-audit harness for the RubyGems + Bundler mono-repo.
#
# This harness scans every Bundler lockfile that the project ships under
# `tool/bundler/*_gems.rb.lock` against the community `ruby-advisory-db`
# (via the `bundler-audit` gem) and produces a single, de-duplicated report
# covering the whole mono-repo at once.
#
# It exists because the project keeps several *independent* dependency sets
# (development, linting, RuboCop, Standard, release, test and vendoring), each
# with its own gemfile/lockfile pair. `bundler-audit` natively scans a single
# `Gemfile.lock`; this harness wraps the public `Bundler::Audit` API to scan
# all of them, de-duplicate advisories that appear in more than one lockfile,
# count the total third-party "risk surface" (resolved gem specifications) and
# act as a CI fail-gate.
#
# Usage:
#   ruby tool/audit/audit.rb                 # text report, fail-gate on findings
#   ruby tool/audit/audit.rb --format json   # machine-readable JSON report
#   ruby tool/audit/audit.rb --format markdown --output tool/audit/SECURITY_AUDIT_REPORT.md
#   ruby tool/audit/audit.rb --update        # refresh advisory DB first (needs network)
#   ruby tool/audit/audit.rb --quiet         # suppress per-advisory detail (summary only)
#
# Exit status:
#   0  no actionable advisories were found (after honoring .bundler-audit.yml)
#   1  one or more actionable advisories were found (CI fail-gate)
#   2  a usage / environment error occurred (e.g. bundler-audit not installed)
#
# The set of advisories that are intentionally accepted (triaged) is declared,
# with justification, in the repository-root `.bundler-audit.yml`. Nothing is
# silently suppressed: ignored advisories are still reported, clearly labelled.
# =============================================================================

require "json"
require "optparse"
require "set"
require "time"

begin
  require "bundler"
  require "bundler/audit/scanner"
  require "bundler/audit/database"
  require "bundler/audit/configuration"
rescue LoadError => e
  warn "[audit] Unable to load the 'bundler-audit' gem: #{e.message}"
  warn "[audit] Install it first, e.g.: gem install bundler-audit"
  exit 2
end

module RubygemsAudit
  # Absolute path to the repository root (this file lives in <root>/tool/audit).
  REPO_ROOT = File.expand_path("../..", __dir__)

  # All shipped lockfiles follow the `<name>_gems.rb.lock` convention.
  LOCKFILE_GLOB = File.join(REPO_ROOT, "tool", "bundler", "*_gems.rb.lock")

  # Repository-root bundler-audit configuration (declares triaged advisories).
  CONFIG_FILE = File.join(REPO_ROOT, ".bundler-audit.yml")

  # A single, normalized finding for one (lockfile, advisory, gem) tuple.
  Finding = Struct.new(
    :lockfile, :gem_name, :gem_version, :advisory_id, :cve, :ghsa,
    :title, :url, :criticality, :patched_versions, :ignored,
    keyword_init: true
  )

  # An insecure gem source (git/path/http) found in a lockfile.
  SourceFinding = Struct.new(:lockfile, :source, keyword_init: true)

  # Orchestrates scanning, aggregation, reporting and the fail-gate.
  class Harness
    attr_reader :findings, :source_findings, :surfaces, :lockfiles, :errors

    def initialize(options)
      @options         = options
      @findings        = []
      @source_findings = []
      @surfaces        = {} # lockfile basename => resolved spec count
      @errors          = []
      @lockfiles       = Dir.glob(LOCKFILE_GLOB).sort
    end

    # Refresh the local copy of ruby-advisory-db. Returns true on success.
    def update_database!
      if Bundler::Audit::Database.exists?
        Bundler::Audit::Database.update!(quiet: @options[:quiet])
      else
        Bundler::Audit::Database.download(quiet: @options[:quiet])
      end
      true
    rescue StandardError => e
      @errors << "advisory-db refresh failed: #{e.message}"
      false
    end

    # Run the audit across every discovered lockfile.
    def run
      if @lockfiles.empty?
        @errors << "no lockfiles matched #{LOCKFILE_GLOB}"
        return self
      end

      database = Bundler::Audit::Database.new

      @lockfiles.each do |path|
        basename = File.basename(path)
        scan_lockfile(path, basename, database)
        @surfaces[basename] = count_surfaces(path)
      end

      self
    end

    # ---- Aggregations -------------------------------------------------------

    # Advisories that are NOT triaged (the ones that fail the gate).
    def actionable_findings
      @findings.reject(&:ignored)
    end

    # Unique advisory ids across all lockfiles (the canonical "advisory" count).
    def unique_advisories(scope = :actionable)
      pool = scope == :all ? @findings : actionable_findings
      pool.map(&:advisory_id).uniq.sort
    end

    # Unique vulnerable gems across all lockfiles.
    def vulnerable_gems(scope = :actionable)
      pool = scope == :all ? @findings : actionable_findings
      pool.map(&:gem_name).uniq.sort
    end

    def total_surfaces
      @surfaces.values.sum
    end

    # The fail-gate result: true means "safe / pass".
    def pass?
      @errors.empty? && actionable_findings.empty?
    end

    private

    # Scan a single lockfile and append normalized findings.
    def scan_lockfile(path, basename, database)
      root     = File.dirname(path)
      scanner  = Bundler::Audit::Scanner.new(root, basename, database, CONFIG_FILE)
      ignored  = scanner.config.ignore.to_a

      # scan_specs yields UnpatchedGem results; scan_sources yields InsecureSource.
      scanner.scan_sources do |result|
        @source_findings << SourceFinding.new(lockfile: basename, source: result.source)
      end

      scanner.scan_specs do |result|
        adv = result.advisory
        @findings << Finding.new(
          lockfile: basename,
          gem_name: result.gem.name,
          gem_version: result.gem.version.to_s,
          advisory_id: adv.id,
          cve: adv.cve_id,
          ghsa: adv.ghsa_id,
          title: adv.title.to_s.strip,
          url: adv.url,
          criticality: (adv.criticality || :unknown).to_s,
          patched_versions: Array(adv.patched_versions).map(&:to_s),
          ignored: ignored.include?(adv.id) ||
                              (adv.cve_id && ignored.include?(adv.cve_id)) ||
                              (adv.ghsa_id && ignored.include?(adv.ghsa_id))
        )
      end
    rescue Bundler::GemfileLockNotFound => e
      @errors << "#{basename}: #{e.message}"
    rescue StandardError => e
      @errors << "#{basename}: #{e.class}: #{e.message}"
    end

    # Count the resolved gem specifications (the dependency "risk surface").
    def count_surfaces(path)
      Bundler::LockfileParser.new(File.read(path)).specs.size
    rescue StandardError
      # Fall back to a line-based count of the GEM `specs:` section.
      in_specs = false
      count = 0
      File.foreach(path) do |line|
        if line.start_with?("  specs:")
          in_specs = true
          next
        end
        in_specs = false if in_specs && line =~ /\A[A-Z]/
        count += 1 if in_specs && line =~ /\A    \S/
      end
      count
    end
  end

  # Renders a Harness result in text, json or markdown.
  class Reporter
    SEVERITY_ORDER = { "critical" => 0, "high" => 1, "medium" => 2,
                       "low" => 3, "unknown" => 4 }.freeze

    def initialize(harness, options)
      @h = harness
      @options = options
    end

    def render
      case @options[:format]
      when "json"     then render_json
      when "markdown" then render_markdown
      else                 render_text
      end
    end

    private

    def grouped_by_gem
      @h.findings.group_by(&:gem_name).sort_by do |gem, fs|
        [SEVERITY_ORDER.fetch(min_criticality(fs), 9), gem]
      end
    end

    def min_criticality(findings)
      findings.map {|f| f.criticality.downcase }.
              min_by {|c| SEVERITY_ORDER.fetch(c, 9) } || "unknown"
    end

    def render_text
      out = +""
      out << "RubyGems/Bundler dependency security audit\n"
      out << ("=" * 60) << "\n"
      out << "Lockfiles scanned : #{@h.lockfiles.size}\n"
      out << "Risk surfaces     : #{@h.total_surfaces} resolved gem specs\n"
      out << "Unique advisories : #{@h.unique_advisories(:all).size} " \
             "(#{@h.actionable_findings.map(&:advisory_id).uniq.size} actionable, " \
             "#{(@h.unique_advisories(:all) - @h.unique_advisories(:actionable)).size} triaged)\n"
      out << "Vulnerable gems   : #{@h.vulnerable_gems(:all).size}\n"
      out << "Insecure sources  : #{@h.source_findings.size}\n"
      out << "\n"

      unless @h.errors.empty?
        out << "ERRORS:\n"
        @h.errors.each {|e| out << "  ! #{e}\n" }
        out << "\n"
      end

      grouped_by_gem.each do |gem, fs|
        versions = fs.map(&:gem_version).uniq.join(", ")
        lockfiles = fs.map(&:lockfile).uniq.sort.join(", ")
        out << "#{gem} (#{versions}) — in: #{lockfiles}\n"
        next if @options[:quiet]

        fs.map(&:advisory_id).uniq.sort.each do |aid|
          f = fs.find {|x| x.advisory_id == aid }
          flag = f.ignored ? " [TRIAGED/IGNORED]" : ""
          fix = f.patched_versions.empty? ? "no patched version" : f.patched_versions.join(" OR ")
          out << "    - #{f.ghsa || f.advisory_id}#{f.cve ? " (#{f.cve})" : ""} " \
                 "[#{f.criticality}]#{flag}\n"
          out << "        #{f.title}\n"
          out << "        fix: update to #{fix}\n"
        end
      end

      out << "\n"
      if @h.pass?
        out << "RESULT: PASS — no actionable advisories.\n"
      else
        count = @h.actionable_findings.map(&:advisory_id).uniq.size
        out << "RESULT: FAIL — #{count} actionable advisory(ies).\n"
      end
      out
    end

    def render_json
      payload = {
        generated_at: Time.now.utc.iso8601,
        lockfiles: @h.lockfiles.map {|p| File.basename(p) },
        summary: {
          risk_surfaces: @h.total_surfaces,
          surfaces_by_lockfile: @h.surfaces,
          unique_advisories_total: @h.unique_advisories(:all).size,
          unique_advisories_actionable: @h.actionable_findings.map(&:advisory_id).uniq.size,
          unique_advisories_triaged: (@h.unique_advisories(:all) - @h.unique_advisories(:actionable)).size,
          vulnerable_gems: @h.vulnerable_gems(:all).size,
          insecure_sources: @h.source_findings.size,
          pass: @h.pass?,
        },
        errors: @h.errors,
        findings: @h.findings.map(&:to_h),
        insecure_sources: @h.source_findings.map(&:to_h),
      }
      JSON.pretty_generate(payload) << "\n"
    end

    def render_markdown
      total = @h.unique_advisories(:all).size
      actionable = @h.actionable_findings.map(&:advisory_id).uniq.size
      triaged = total - actionable
      out = +""
      out << "# RubyGems + Bundler — Dependency Security Audit Report\n\n"
      out << "_Generated by `tool/audit/audit.rb` at #{Time.now.utc.iso8601}._\n\n"
      out << "## Summary\n\n"
      out << "| Metric | Value |\n|---|---|\n"
      out << "| Lockfiles scanned | #{@h.lockfiles.size} |\n"
      out << "| Risk surfaces (resolved gem specs) | #{@h.total_surfaces} |\n"
      out << "| Unique advisories (total) | #{total} |\n"
      out << "| Unique advisories (actionable) | #{actionable} |\n"
      out << "| Unique advisories (triaged/accepted) | #{triaged} |\n"
      out << "| Vulnerable gems | #{@h.vulnerable_gems(:all).size} |\n"
      out << "| Insecure sources | #{@h.source_findings.size} |\n"
      out << "| Fail-gate result | #{@h.pass? ? "PASS" : "FAIL"} |\n\n"

      out << "## Risk surface by lockfile\n\n"
      out << "| Lockfile | Resolved gem specs |\n|---|---|\n"
      @h.surfaces.sort.each {|name, n| out << "| `#{name}` | #{n} |\n" }
      out << "| **Total** | **#{@h.total_surfaces}** |\n\n"

      out << "## Advisories\n\n"
      if @h.findings.empty?
        out << "No advisories found. \xE2\x9C\x85\n\n".dup.force_encoding("UTF-8")
      else
        out << "| Gem | Version | Advisory | Severity | Lockfile(s) | Fix | State |\n"
        out << "|---|---|---|---|---|---|---|\n"
        grouped_by_gem.each do |gem, fs|
          fs.map(&:advisory_id).uniq.sort.each do |aid|
            f = fs.find {|x| x.advisory_id == aid }
            id = f.ghsa || f.advisory_id
            id = "#{id} / #{f.cve}" if f.cve
            fix = f.patched_versions.empty? ? "—" : f.patched_versions.join(" OR ")
            state = f.ignored ? "triaged" : "actionable"
            lfs = fs.select {|x| x.advisory_id == aid }.map(&:lockfile).uniq.sort.join(", ")
            out << "| `#{gem}` | #{f.gem_version} | #{id} | #{f.criticality} | #{lfs} | `#{fix}` | #{state} |\n"
          end
        end
        out << "\n"
      end
      out
    end
  end

  module CLI
    def self.parse(argv)
      options = { format: "text", update: false, quiet: false, output: nil }
      parser = OptionParser.new do |o|
        o.banner = "Usage: ruby tool/audit/audit.rb [options]"
        o.on("-f", "--format FORMAT", %w[text json markdown],
             "Output format (text, json, markdown). Default: text") {|v| options[:format] = v }
        o.on("-u", "--update", "Refresh the ruby-advisory-db before scanning") { options[:update] = true }
        o.on("-o", "--output FILE", "Write the report to FILE instead of stdout") {|v| options[:output] = v }
        o.on("-q", "--quiet", "Summary only; suppress per-advisory detail") { options[:quiet] = true }
        o.on("-h", "--help", "Show this help") do
          puts o
          exit 0
        end
      end
      parser.parse!(argv)
      options
    end

    def self.run(argv)
      options = parse(argv)
      harness = Harness.new(options)
      harness.update_database! if options[:update]
      harness.run

      report = Reporter.new(harness, options).render
      if options[:output]
        path = File.absolute_path(options[:output], REPO_ROOT)
        File.write(path, report)
        warn "[audit] report written to #{path}"
      else
        puts report
      end

      # Surface environment errors distinctly from a clean fail-gate.
      exit 2 unless harness.errors.empty?
      exit(harness.pass? ? 0 : 1)
    end
  end
end

RubygemsAudit::CLI.run(ARGV) if $PROGRAM_NAME == __FILE__
