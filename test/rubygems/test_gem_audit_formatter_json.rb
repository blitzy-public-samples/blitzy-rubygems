# frozen_string_literal: true

require_relative "helper"
require "rubygems/audit"
require "stringio"
require "open3"

class TestGemAuditFormatterJson < Gem::TestCase
  def test_empty_report_is_byte_exact
    out = render(build_report(vulns: [], gems_audited: 5))
    assert_equal '{"vulnerabilities":[],"summary":{"total":0,"gems_audited":5}}', out
  end

  def test_empty_report_has_no_trailing_newline
    out = render(build_report(vulns: [], gems_audited: 0))
    refute out.end_with?("\n")
  end

  def test_single_vulnerability_schema_and_values
    vuln = build_vuln(severity: "high", patched_versions: ["2.0.2", "2.1.4"])
    out = render(build_report(vulns: [vuln], gems_audited: 42))
    doc = JSON.parse(out)
    assert_equal %w[vulnerabilities summary], doc.keys
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

  def test_single_vulnerability_is_byte_exact
    vuln = build_vuln(severity: "high", patched_versions: ["2.0.2", "2.1.4"])
    out = render(build_report(vulns: [vuln], gems_audited: 42))
    expected = '{"vulnerabilities":[{"gem_name":"rack","installed_version":"2.0.1",' \
               '"cve_id":"CVE-2018-16471","severity":"high",' \
               '"patched_versions":["2.0.2","2.1.4"]}],' \
               '"summary":{"total":1,"gems_audited":42}}'
    assert_equal expected, out
  end

  def test_many_vulnerabilities_preserve_order
    first = build_vuln(gem_name: "rack", severity: "high")
    second = build_vuln(gem_name: "nokogiri", installed_version: "1.10.0",
                        cve_id: "CVE-2019-5477", severity: "critical",
                        patched_versions: ["1.10.4"])
    out = render(build_report(vulns: [first, second], gems_audited: 10))
    doc = JSON.parse(out)
    assert_equal 2, doc["vulnerabilities"].size
    assert_equal 2, doc["summary"]["total"]
    assert_equal "rack", doc["vulnerabilities"][0]["gem_name"]
    assert_equal "nokogiri", doc["vulnerabilities"][1]["gem_name"]
  end

  def test_null_severity_is_present_not_omitted
    out = render(build_report(vulns: [build_vuln(severity: nil)], gems_audited: 1))
    assert out.include?('"severity":null')
    v = JSON.parse(out)["vulnerabilities"].first
    assert v.key?("severity")
    assert_nil v["severity"]
  end

  def test_empty_patched_versions_renders_array
    out = render(build_report(vulns: [build_vuln(patched_versions: [])], gems_audited: 1))
    assert out.include?('"patched_versions":[]')
    assert_equal [], JSON.parse(out)["vulnerabilities"].first["patched_versions"]
  end

  def test_nil_patched_versions_coerced_to_array
    out = render(build_report(vulns: [build_vuln(patched_versions: nil)], gems_audited: 1))
    assert out.include?('"patched_versions":[]')
    assert_equal [], JSON.parse(out)["vulnerabilities"].first["patched_versions"]
  end

  def test_round_trip_parse_equals_expected_structure
    vuln = build_vuln(severity: "high", patched_versions: ["2.0.2"])
    out = render(build_report(vulns: [vuln], gems_audited: 3))
    parsed = nil
    assert_nothing_raised { parsed = JSON.parse(out) }
    expected_vuln = {
      "gem_name" => "rack",
      "installed_version" => "2.0.1",
      "cve_id" => "CVE-2018-16471",
      "severity" => "high",
      "patched_versions" => ["2.0.2"],
    }
    expected = {
      "vulnerabilities" => [expected_vuln],
      "summary" => { "total" => 1, "gems_audited" => 3 },
    }
    assert_equal expected, parsed
  end

  def test_require_chain_is_warning_free
    # Loading the audit subsystem must not emit "circular require considered
    # harmful" warnings. Each concrete formatter requires the registry, so the
    # registry must NOT require the concrete formatters back; "rubygems/audit"
    # owns the load order (registry first, then the concrete formatters).
    #
    # The check runs in a fresh child process under -w because the require has
    # already executed in this process (the constant is loaded), so an in-process
    # re-require would be a no-op and could not surface the warning.
    lib = File.expand_path("../../lib", __dir__)
    _out, err, status = Open3.capture3(
      Gem.ruby, "-w", "-I", lib, "-e", 'require "rubygems/audit"'
    )

    assert status.success?, "requiring rubygems/audit failed:\n#{err}"
    refute_match(/circular require/, err,
                 "circular require warning in the audit require chain:\n#{err}")
  end

  private

  def render(report)
    io = StringIO.new
    Gem::Audit::Formatter::JSON.print_report(report, io)
    io.string
  end

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
