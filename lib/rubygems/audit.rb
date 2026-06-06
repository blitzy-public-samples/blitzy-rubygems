# frozen_string_literal: true

##
# = Auditing gems for known vulnerabilities
#
# Gem::Audit is the entry point for RubyGems' vulnerability-audit subsystem. It
# inspects the locally installed gems, matches them against known security
# advisories, and produces a Gem::Audit::Report describing the vulnerabilities
# that were found together with the number of gems that were audited.
#
# The report is rendered for the user by a pluggable formatter (see
# Gem::Audit::Formatter). The +gem audit+ command selects a formatter through
# its <code>--format</code> option -- for example <code>--format json</code> --
# and writes the formatted report to its output stream while routing all
# diagnostics to standard error.
#
# Audit results are represented by Gem::Audit::Report and its nested
# Gem::Audit::Report::Vulnerability value object, both defined in
# "audit/report" and loaded at the end of this file.

module Gem::Audit
  ##
  # Run a vulnerability audit of the locally installed gems and return the
  # result as a Gem::Audit::Report.
  #
  # +options+ is an optional Hash mirroring the parsed +gem audit+ command
  # options. It is accepted for forward compatibility and serves as the
  # integration seam through which the (separately owned) vulnerability-matching
  # engine and the <code>--severity</code> filter inject their results. This
  # entry point performs no advisory matching, no filtering, and no networking
  # of its own.
  #
  # The returned report always exposes:
  #
  # * +vulnerabilities+ -- an Array of detected matches. It is empty until the
  #   matching engine is wired in, which makes <code>gem audit --format json</code>
  #   emit the documented empty-result document.
  # * +gems_audited+ -- a non-negative Integer count of the gems inspected.
  #
  # Returns a Gem::Audit::Report.

  def self.audit(options = {})
    # The vulnerability-matching engine is owned by a sibling story and is not
    # wired in here, so no advisories are matched and the audit reports zero
    # vulnerabilities. Reading from +options+ keeps this method an injection
    # seam. An explicit Array type check -- rather than Kernel#Array -- enforces
    # the edge contract that a non-array or absent match-result is treated as zero
    # vulnerabilities: +nil+ or any non-Array value becomes +[]+, while an Array is
    # passed through unchanged. (Kernel#Array would instead wrap a single non-Array
    # match into a one-element array and report a false vulnerability count.) This
    # normalization is kept consistent with Gem::Audit::Report#initialize.
    raw = options[:vulnerabilities]
    vulnerabilities = raw.is_a?(Array) ? raw : []

    # Count the gems that were audited: the latest version of every installed
    # gem. Guard against load errors (for example a missing or empty gem home)
    # so auditing an environment with no gems yields 0 instead of raising.
    gems_audited = begin
      Gem::Specification.latest_specs(true).size
    rescue StandardError
      0
    end

    Gem::Audit::Report.new(vulnerabilities: vulnerabilities, gems_audited: gems_audited)
  end
end

# Load the audit subsystem's sub-files. Order matters and mirrors the
# namespace+subfiles pattern used by "rubygems/security":
#
# * "audit/report" defines Gem::Audit::Report, returned by Gem::Audit.audit
#   above;
# * "audit/formatter" defines the formatter registry; and
# * "audit/formatter/text" and "audit/formatter/json" define the concrete,
#   self-registering formatters.
#
# The registry is required BEFORE the concrete formatters on purpose: each
# concrete formatter opens the Gem::Audit::Formatter namespace and calls
# Gem::Audit::Formatter.register, both of which require the registry to already
# be defined. Loading the concrete formatters here -- rather than from within
# the registry file -- keeps the dependency strictly one-directional
# (concrete -> registry) and therefore avoids the require cycle that would
# otherwise emit "circular require considered harmful" warnings.
#
# Requiring them here -- after Gem::Audit is declared -- ensures the report
# data structure, the formatter registry, and both formatters are all available
# as soon as anything requires "rubygems/audit".
require_relative "audit/report"
require_relative "audit/formatter"
require_relative "audit/formatter/text"
require_relative "audit/formatter/json"
