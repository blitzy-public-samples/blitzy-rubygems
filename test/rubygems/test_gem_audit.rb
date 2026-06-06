# frozen_string_literal: true

require_relative "helper"
require "rubygems/audit"

##
# Unit tests for the Gem::Audit orchestration entry point (Gem::Audit.audit).
#
# These tests exercise the real method directly -- they neither stub it (as the
# command suite does) nor bypass it by constructing a Gem::Audit::Report by hand
# (as the formatter suite does). They therefore cover the documented
# match-result normalization edge contract and the gems_audited counting/rescue
# path of the audit subsystem's public entry point.

class TestGemAudit < Gem::TestCase
  def test_audit_passes_array_vulnerabilities_through
    a = vuln("rack")
    b = vuln("nokogiri")

    report = Gem::Audit.audit(vulnerabilities: [a, b])

    assert_kind_of Gem::Audit::Report, report
    assert_equal [a, b], report.vulnerabilities
    assert_equal 2, report.total
  end

  def test_audit_nil_vulnerabilities_normalizes_to_empty_array
    assert_equal [], Gem::Audit.audit(vulnerabilities: nil).vulnerabilities
  end

  def test_audit_non_array_vulnerabilities_normalizes_to_empty_array
    # The entry point enforces its edge contract with an explicit is_a?(Array)
    # check -- NOT Kernel#Array, which would wrap a single non-Array value into a
    # one-element array (e.g. Array("oops") => ["oops"]) and report a false
    # vulnerability count. A String and a plain Object must both normalize to [].
    assert_equal [], Gem::Audit.audit(vulnerabilities: "oops").vulnerabilities
    assert_equal [], Gem::Audit.audit(vulnerabilities: Object.new).vulnerabilities
  end

  def test_audit_absent_vulnerabilities_key_defaults_to_empty_array
    assert_equal [], Gem::Audit.audit({}).vulnerabilities
    assert_equal [], Gem::Audit.audit.vulnerabilities
  end

  def test_audit_gems_audited_is_non_negative_integer
    report = Gem::Audit.audit

    assert_kind_of Integer, report.gems_audited
    assert_operator report.gems_audited, :>=, 0
  end

  def test_audit_gems_audited_is_zero_when_latest_specs_raises
    # Auditing an environment whose specs cannot be loaded must yield a count of
    # 0 rather than raising: Gem::Audit.audit guards the count with a
    # StandardError rescue. Force latest_specs to raise to exercise that branch.
    Gem::Specification.stub(:latest_specs, ->(*) { raise StandardError, "boom" }) do
      assert_equal 0, Gem::Audit.audit.gems_audited
    end
  end

  private

  def vuln(name)
    Gem::Audit::Report::Vulnerability.new(
      gem_name: name, installed_version: "1.0.0", cve_id: "CVE-0000-0000"
    )
  end
end
