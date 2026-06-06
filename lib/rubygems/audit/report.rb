# frozen_string_literal: true

##
# Gem::Audit::Report is the match-result data structure produced by an audit
# run. It carries the set of detected vulnerabilities and a count of audited
# gems, and is consumed by the audit formatters.

class Gem::Audit::Report
  ##
  # The detected vulnerabilities, always an Array (possibly empty).

  attr_reader :vulnerabilities

  ##
  # The number of gems that were audited.

  attr_reader :gems_audited

  def initialize(vulnerabilities: [], gems_audited: 0)
    # Enforce the edge contract that a non-array or absent match-result is
    # treated as zero vulnerabilities: only an actual Array is accepted, while
    # +nil+ or any other non-Array value normalizes to +[]+. Kernel#Array is
    # deliberately NOT used here -- it would wrap a single non-Array value into a
    # one-element array (e.g. Array(advisory) => [advisory]) and report a false
    # vulnerability total.
    @vulnerabilities = vulnerabilities.is_a?(Array) ? vulnerabilities : []
    # +gems_audited+ is the count of gems that were inspected, which is always
    # non-negative. Coerce to Integer and clamp at 0 so a stray negative value
    # can never be reported, keeping the field consistent with its documented
    # non-negative contract.
    @gems_audited = [gems_audited.to_i, 0].max
  end

  ##
  # Total number of detected vulnerabilities.

  def total
    @vulnerabilities.size
  end

  ##
  # A single vulnerability match. Exposes exactly the fields required by the
  # JSON serializer.

  class Vulnerability
    attr_reader :gem_name, :installed_version, :cve_id, :severity, :patched_versions

    def initialize(gem_name:, installed_version:, cve_id:, severity: nil, patched_versions: [])
      @gem_name = gem_name
      @installed_version = installed_version
      @cve_id = cve_id
      @severity = severity
      @patched_versions = Array(patched_versions)
    end
  end
end
