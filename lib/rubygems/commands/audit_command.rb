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
    format = options[:format]

    unless %w[text json].include?(format)
      ui.errs.puts "ERROR: Unknown format '#{format}'. Valid options: text, json."
      terminate_interaction 1
    end

    if format == "json"
      execute_json
    else
      execute_text
    end
  end

  private

  ##
  # Render the audit report in the default, human-readable text format.
  #
  # This is the unchanged, backward-compatible output path: the audit runs under
  # the command's normal user interaction, so informational messages and
  # warnings keep their existing destinations.

  def execute_text
    report = Gem::Audit.audit(options)
    Gem::Audit::Formatter.for("text").print_report(report, ui.outs)
  end

  ##
  # Render the audit report as a single JSON document on standard output.
  #
  # AC-4 requires that, in JSON mode, standard output carry ONLY the JSON
  # document while every diagnostic -- informational messages AND warnings -- is
  # written to standard error. RubyGems' +say+ and informational +alert+ helpers
  # write to standard output by default, so any diagnostic emitted while the
  # audit runs would otherwise be interleaved with the JSON document, corrupting
  # it for a strict parser (and for a downstream <code>| jq</code>).
  #
  # To guarantee a clean channel, the real standard-output stream is captured up
  # front as the sole JSON sink, and the audit is executed with all diagnostics
  # redirected to standard error (see #with_diagnostics_on_stderr). Only after
  # the audit has completed is the serialized document written to the captured
  # output stream, so nothing but the JSON document can reach standard output.

  def execute_json
    out = ui.outs

    report = with_diagnostics_on_stderr { Gem::Audit.audit(options) }

    Gem::Audit::Formatter.for("json").print_report(report, out)
  end

  ##
  # Run +block+ with the command's informational output redirected to standard
  # error for the duration of the call, and return the block's value.
  #
  # A temporary Gem::StreamUI is installed whose output stream is the current
  # error stream, so +say+ and informational +alert+ (normally standard output)
  # join +alert_warning+/+alert_error+ (already standard error) on standard
  # error. The original UI -- and therefore the original standard-output stream
  # reserved for the JSON document -- is restored automatically when the block
  # returns, because Gem::DefaultUserInteraction#use_ui swaps the UI back in an
  # +ensure+ block even if the audit raises.

  def with_diagnostics_on_stderr
    current = ui
    err_stream = current.errs
    diagnostics_ui = Gem::StreamUI.new(current.ins, err_stream, err_stream, current.tty?)

    use_ui(diagnostics_ui) { yield }
  end
end
