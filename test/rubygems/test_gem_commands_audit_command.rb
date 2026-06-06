# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/audit_command"

class TestGemCommandsAuditCommand < Gem::TestCase
  def setup
    super
    @cmd = Gem::Commands::AuditCommand.new
  end

  def test_execute_json_writes_parseable_document_to_stdout # AC-1
    report = build_report(vulns: [build_vuln(severity: "high")], gems_audited: 1)
    @cmd.options[:format] = "json"
    Gem::Audit.stub(:audit, report) do
      use_ui @ui do
        @cmd.execute
      end
    end
    assert_nothing_raised { JSON.parse(@ui.output) }
    assert_equal "", @ui.error
  end

  def test_execute_json_schema_for_one_advisory # AC-2
    vuln = build_vuln(gem_name: "rack", installed_version: "2.0.1",
                      cve_id: "CVE-2018-16471", severity: "high",
                      patched_versions: ["2.0.2", "2.1.4"])
    @cmd.options[:format] = "json"
    Gem::Audit.stub(:audit, build_report(vulns: [vuln], gems_audited: 42)) do
      use_ui @ui do
        @cmd.execute
      end
    end
    doc = JSON.parse(@ui.output)
    assert_equal %w[vulnerabilities summary], doc.keys
    assert_kind_of Array, doc["vulnerabilities"]
    v = doc["vulnerabilities"].first
    assert_equal %w[gem_name installed_version cve_id severity patched_versions], v.keys
    assert_equal "rack", v["gem_name"]
    assert_equal "2.0.1", v["installed_version"]
    assert_equal "CVE-2018-16471", v["cve_id"]
    assert_equal "high", v["severity"]
    assert_equal ["2.0.2", "2.1.4"], v["patched_versions"]
    assert_equal 1, doc["summary"]["total"]
    assert_equal 42, doc["summary"]["gems_audited"]
  end

  def test_execute_json_empty_is_byte_exact_and_exits_zero # AC-3
    @cmd.options[:format] = "json"
    Gem::Audit.stub(:audit, build_report(vulns: [], gems_audited: 7)) do
      use_ui @ui do
        @cmd.execute
      end
    end
    assert_equal '{"vulnerabilities":[],"summary":{"total":0,"gems_audited":7}}', @ui.output
    assert_equal "", @ui.error
    refute @ui.terminated?
  end

  def test_execute_json_routes_diagnostics_to_stderr # AC-4
    report = build_report(vulns: [build_vuln(severity: "high")], gems_audited: 3)
    audit = lambda do |_options|
      @cmd.alert_warning "advisory database is stale"
      report
    end
    @cmd.options[:format] = "json"
    Gem::Audit.stub(:audit, audit) do
      use_ui @ui do
        @cmd.execute
      end
    end
    parsed = JSON.parse(@ui.output)
    assert parsed.key?("vulnerabilities")
    refute_match(/WARNING|stale/, @ui.output)
    assert_match(/advisory database is stale/, @ui.error)
  end

  def test_execute_json_routes_info_diagnostics_to_stderr # AC-4 (informational)
    # Informational `alert`/`say` output is written to STDOUT by RubyGems
    # convention. In JSON mode it MUST be redirected to STDERR so the JSON
    # document on STDOUT remains a single, parseable payload. This is the
    # regression guard for the AC-4 stdout-contamination bug: without the
    # redirect, "INFO:  ..." would be interleaved with the JSON and JSON.parse
    # would raise.
    report = build_report(vulns: [build_vuln(severity: "high")], gems_audited: 3)
    audit = lambda do |_options|
      @cmd.alert "audit info diagnostic"
      @cmd.say "a plain status line"
      report
    end
    @cmd.options[:format] = "json"
    Gem::Audit.stub(:audit, audit) do
      use_ui @ui do
        @cmd.execute
      end
    end
    # STDOUT is exactly one parseable JSON document and nothing else.
    parsed = nil
    assert_nothing_raised { parsed = JSON.parse(@ui.output) }
    assert parsed.key?("vulnerabilities")
    refute_match(/INFO:|audit info diagnostic|a plain status line/, @ui.output)
    # The diagnostics are present only on STDERR.
    assert_match(/audit info diagnostic/, @ui.error)
    assert_match(/a plain status line/, @ui.error)
  end

  def test_execute_invalid_format_writes_exact_error_and_exits_one # AC-5
    @cmd.options[:format] = "xml"
    use_ui @ui do
      e = assert_raise Gem::MockGemUi::TermError do
        @cmd.execute
      end
      assert_equal 1, e.exit_code
    end
    assert_equal "ERROR: Unknown format 'xml'. Valid options: text, json.\n", @ui.error
    assert_equal "", @ui.output
  end

  def test_execute_json_null_severity_present_not_omitted # edge
    @cmd.options[:format] = "json"
    Gem::Audit.stub(:audit, build_report(vulns: [build_vuln(severity: nil)], gems_audited: 1)) do
      use_ui @ui do
        @cmd.execute
      end
    end
    assert_match(/"severity":null/, @ui.output)
    v = JSON.parse(@ui.output)["vulnerabilities"].first
    assert v.key?("severity")
    assert_nil v["severity"]
  end

  def test_execute_json_empty_patched_versions # edge
    @cmd.options[:format] = "json"
    Gem::Audit.stub(:audit, build_report(vulns: [build_vuln(patched_versions: [])], gems_audited: 1)) do
      use_ui @ui do
        @cmd.execute
      end
    end
    assert_match(/"patched_versions":\[\]/, @ui.output)
    assert_equal [], JSON.parse(@ui.output)["vulnerabilities"].first["patched_versions"]
  end

  # The default (no --format) path must produce the EXACT human-readable report
  # so that a broken text formatter -- one that omits the CVE/severity/patched
  # data or changes the wording -- cannot pass (R2 backward compatibility).
  def test_execute_text_default_is_unchanged # edge - backward compat (R2)
    report = build_report(vulns: [build_vuln(severity: "high")], gems_audited: 1)
    Gem::Audit.stub(:audit, report) do
      use_ui @ui do
        @cmd.execute
      end
    end
    expected = "rack 2.0.1 (CVE-2018-16471): severity high; patched: none\n" \
               "1 vulnerability found across 1 gem audited.\n"
    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_explicit_format_text_behaves_like_default # edge (R2)
    report = build_report(vulns: [build_vuln(severity: "high")], gems_audited: 1)
    @cmd.handle_options %w[--format text]
    Gem::Audit.stub(:audit, report) do
      use_ui @ui do
        @cmd.execute
      end
    end
    expected = "rack 2.0.1 (CVE-2018-16471): severity high; patched: none\n" \
               "1 vulnerability found across 1 gem audited.\n"
    assert_equal expected, @ui.output
    assert_equal "", @ui.error
  end

  def test_execute_json_honors_already_filtered_severity_set # edge
    high = build_vuln(gem_name: "rack", severity: "high")
    critical = build_vuln(gem_name: "nokogiri", installed_version: "1.10.0",
                          cve_id: "CVE-2019-5477", severity: "critical",
                          patched_versions: ["1.10.4"])
    @cmd.options[:format] = "json"
    @cmd.options[:severity] = "high"
    Gem::Audit.stub(:audit, build_report(vulns: [high, critical], gems_audited: 5)) do
      use_ui @ui do
        @cmd.execute
      end
    end
    doc = JSON.parse(@ui.output)
    assert_equal %w[high critical], doc["vulnerabilities"].map {|v| v["severity"] }
    assert_equal 2, doc["summary"]["total"]
    refute @ui.terminated?
  end

  private

  def build_report(vulns: [], gems_audited: 0)
    Gem::Audit::Report.new(vulnerabilities: vulns, gems_audited: gems_audited)
  end

  def build_vuln(gem_name: "rack", installed_version: "2.0.1",
    cve_id: "CVE-2018-16471", severity: nil, patched_versions: [])
    Gem::Audit::Report::Vulnerability.new(
      gem_name: gem_name, installed_version: installed_version,
      cve_id: cve_id, severity: severity, patched_versions: patched_versions
    )
  end
end
