# frozen_string_literal: true

# Ensure the formatter registry (Gem::Audit::Formatter) is defined before this
# concrete formatter is opened and self-registers below. This require is
# one-directional and cycle-free: the registry never requires the concrete
# formatters back (see lib/rubygems/audit.rb, which loads the registry first and
# then the concrete formatters).
require_relative "../formatter"

##
# Gem::Audit::Formatter::Text is the default, human-readable audit formatter.
# It is the unchanged default output path for +gem audit+.

class Gem::Audit::Formatter::Text
  def self.print_report(report, io)
    vulns = Array(report.vulnerabilities)

    vulns.each do |v|
      patched = Array(v.patched_versions)
      patched_str = patched.empty? ? "none" : patched.join(", ")
      severity = v.severity || "unknown"
      io.puts "#{v.gem_name} #{v.installed_version} (#{v.cve_id}): " \
              "severity #{severity}; patched: #{patched_str}"
    end

    io.puts "#{vulns.size} vulnerabilit#{vulns.size == 1 ? "y" : "ies"} found " \
            "across #{report.gems_audited} gem#{report.gems_audited == 1 ? "" : "s"} audited."
  end

  Gem::Audit::Formatter.register("text", self)
end
