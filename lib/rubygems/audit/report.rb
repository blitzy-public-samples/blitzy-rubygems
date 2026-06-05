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
    @vulnerabilities = Array(vulnerabilities)
    @gems_audited = gems_audited.to_i
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
