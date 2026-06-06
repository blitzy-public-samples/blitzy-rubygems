# frozen_string_literal: true

require_relative "../command"
require_relative "../audit"

##
# Gem::Commands::AuditCommand checks the gems installed in the current
# environment against known security vulnerability advisories.
#
# It supports two output formats, selected with the +--format+ option: the
# default human-readable +text+ format and a machine-readable +json+ format.
# In +json+ mode the JSON document is the only thing written to standard
# output; all diagnostics are written to standard error.

class Gem::Commands::AuditCommand < Gem::Command
  def initialize
    super "audit", "Check installed gems for known vulnerabilities", format: "text"

    add_option("--format FORMAT", "Output format: text (default) or json") do |value, options|
      options[:format] = value
    end
  end

  def defaults_str # :nodoc:
    "--format text"
  end

  def description # :nodoc:
    <<-EOF
The audit command checks the gems installed in your environment against known
security vulnerability advisories and reports any matches.

By default the report is printed in a human-readable text format. Use the
--format option to select the output format:

  text    Human-readable output (the default).
  json    A single machine-readable JSON document written to standard output.
          In this mode standard output contains ONLY the JSON document; every
          warning and informational message is written to standard error, so
          the output can be piped to tools such as jq.

The JSON document has the following schema:

  {
    "vulnerabilities": [
      {
        "gem_name": "rack",
        "installed_version": "2.0.1",
        "cve_id": "CVE-XXXX-XXXX",
        "severity": "high",            // string, or null when unknown (key always present)
        "patched_versions": ["2.0.2"]   // array of strings, may be empty []
      }
    ],
    "summary": { "total": 1, "gems_audited": 42 }
  }

When no vulnerabilities are found the document is:

  {"vulnerabilities":[],"summary":{"total":0,"gems_audited":<count>}}

The command exits with a status of 0 on success (including when no
vulnerabilities are found) and a status of 1 when an unknown --format value is
supplied.
    EOF
  end

  def execute
    unless %w[text json].include?(options[:format])
      ui.errs.puts "ERROR: Unknown format '#{options[:format]}'. Valid options: text, json."
      terminate_interaction 1
    end

    report = Gem::Audit.audit(options)

    formatter = Gem::Audit::Formatter.for(options[:format])
    formatter.print_report(report, ui.outs)
  end
end
