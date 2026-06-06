# frozen_string_literal: true

require_relative "../formatter"

##
# Gem::Audit::Formatter::Text renders an audit report as human-readable text on
# the injected output stream. It is the default formatter selected by +gem
# audit+ when no +--format+ option (or +--format text+) is supplied, preserving
# the conventional line-oriented output that humans read directly.

class Gem::Audit::Formatter::Text
  def self.print_report(report, io)
    vulnerabilities = Array(report.vulnerabilities)
    gems_audited = report.gems_audited

    if vulnerabilities.empty?
      io.puts "No vulnerabilities found (#{gems_audited} gems audited)."
      return
    end

    vulnerabilities.each do |vulnerability|
      io.puts "#{vulnerability.gem_name} #{vulnerability.installed_version} (#{vulnerability.cve_id})"
      io.puts "  Severity: #{vulnerability.severity || "unknown"}"

      patched_versions = Array(vulnerability.patched_versions)
      io.puts "  Patched versions: #{patched_versions.join(", ")}" unless patched_versions.empty?
    end

    io.puts
    label = vulnerabilities.size == 1 ? "vulnerability" : "vulnerabilities"
    io.puts "#{vulnerabilities.size} #{label} found (#{gems_audited} gems audited)."
  end

  Gem::Audit::Formatter.register("text", self)
end
