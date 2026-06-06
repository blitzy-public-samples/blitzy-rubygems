# frozen_string_literal: true

require_relative "helper"
require "rubygems/audit"

##
# Unit tests for Gem::Audit::Report, the match-result data structure consumed by
# the audit formatters. These tests exercise the public #total accessor and the
# documented normalization edge contracts of #initialize (non-Array
# vulnerabilities normalize to [], and gems_audited is coerced to a
# non-negative Integer).

class TestGemAuditReport < Gem::TestCase
  def test_total_returns_vulnerability_count
    report = Gem::Audit::Report.new(
      vulnerabilities: [vuln("rack"), vuln("nokogiri"), vuln("rexml")],
      gems_audited: 9
    )

    assert_equal 3, report.total
  end

  def test_total_is_zero_for_empty_report
    assert_equal 0, Gem::Audit::Report.new.total
  end

  def test_array_vulnerabilities_are_passed_through
    v = vuln("rack")

    report = Gem::Audit::Report.new(vulnerabilities: [v], gems_audited: 1)

    assert_equal [v], report.vulnerabilities
  end

  def test_nil_vulnerabilities_normalizes_to_empty_array
    report = Gem::Audit::Report.new(vulnerabilities: nil, gems_audited: 1)

    assert_equal [], report.vulnerabilities
    assert_equal 0, report.total
  end

  def test_non_array_vulnerabilities_normalizes_to_empty_array
    # Kernel#Array is deliberately NOT used: a non-Array value normalizes to []
    # rather than being wrapped into a one-element array. Verify with both a
    # String and a plain Object.
    assert_equal [], Gem::Audit::Report.new(vulnerabilities: "oops").vulnerabilities
    assert_equal [], Gem::Audit::Report.new(vulnerabilities: Object.new).vulnerabilities
  end

  def test_negative_gems_audited_clamps_to_zero
    assert_equal 0, Gem::Audit::Report.new(gems_audited: -5).gems_audited
  end

  def test_gems_audited_is_coerced_to_integer
    assert_equal 3, Gem::Audit::Report.new(gems_audited: 3).gems_audited
  end

  private

  def vuln(name)
    Gem::Audit::Report::Vulnerability.new(
      gem_name: name, installed_version: "1.0.0", cve_id: "CVE-0000-0000"
    )
  end
end
