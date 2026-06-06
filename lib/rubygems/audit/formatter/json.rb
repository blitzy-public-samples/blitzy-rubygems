# frozen_string_literal: true

require "json"

# Ensure the formatter registry (Gem::Audit::Formatter) is defined before this
# concrete formatter is opened and self-registers below. This require is
# one-directional and cycle-free: the registry never requires the concrete
# formatters back (see lib/rubygems/audit.rb, which loads the registry first and
# then the concrete formatters).
require_relative "../formatter"

##
# Gem::Audit::Formatter::JSON serializes an audit report into a single,
# machine-readable JSON document on the injected output stream.

class Gem::Audit::Formatter::JSON
  def self.print_report(report, io)
    vulns = Array(report.vulnerabilities)

    document = {
      "vulnerabilities" => vulns.map do |v|
        {
          "gem_name" => v.gem_name,
          "installed_version" => v.installed_version,
          "cve_id" => v.cve_id,
          "severity" => v.severity,
          "patched_versions" => Array(v.patched_versions),
        }
      end,
      "summary" => {
        "total" => vulns.size,
        "gems_audited" => report.gems_audited,
      },
    }

    io.print ::JSON.generate(document)
  end

  Gem::Audit::Formatter.register("json", self)
end
