# frozen_string_literal: true

require_relative "helper"
require "rubygems/audit"
require "stringio"

##
# Unit tests for Gem::Audit::Formatter::Text, the default human-readable audit
# formatter. These tests lock the exact text contract and exercise the
# formatter's conditional branches: singular vs plural vulnerability/gem wording,
# the "none" vs joined patched-versions rendering, and the nil-severity
# ("unknown") fallback.

class TestGemAuditFormatterText < Gem::TestCase
  def test_multiple_vulnerabilities_plural_join_and_nil_severity
    rack = build_vuln(gem_name: "rack", installed_version: "2.0.1",
                      cve_id: "CVE-2018-16471", severity: nil,
                      patched_versions: ["2.0.2", "2.1.4"])
    nokogiri = build_vuln(gem_name: "nokogiri", installed_version: "1.10.0",
                          cve_id: "CVE-2019-5477", severity: "critical",
                          patched_versions: [])

    out = render(build_report(vulns: [rack, nokogiri], gems_audited: 5))

    expected = "rack 2.0.1 (CVE-2018-16471): severity unknown; patched: 2.0.2, 2.1.4\n" \
               "nokogiri 1.10.0 (CVE-2019-5477): severity critical; patched: none\n" \
               "2 vulnerabilities found across 5 gems audited.\n"
    assert_equal expected, out
  end

  def test_single_vulnerability_singular_wording_and_one_gem
    vuln = build_vuln(severity: "high", patched_versions: [])

    out = render(build_report(vulns: [vuln], gems_audited: 1))

    expected = "rack 2.0.1 (CVE-2018-16471): severity high; patched: none\n" \
               "1 vulnerability found across 1 gem audited.\n"
    assert_equal expected, out
  end

  def test_empty_report_renders_plural_summary_line
    out = render(build_report(vulns: [], gems_audited: 0))

    assert_equal "0 vulnerabilities found across 0 gems audited.\n", out
  end

  private

  def render(report)
    io = StringIO.new
    Gem::Audit::Formatter::Text.print_report(report, io)
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
