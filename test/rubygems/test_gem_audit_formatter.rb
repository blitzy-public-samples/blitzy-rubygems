# frozen_string_literal: true

require_relative "helper"
require "rubygems/audit"

##
# Unit tests for the Gem::Audit::Formatter registry. These tests cover the
# lookup contract of .for/.fetch: returning the registered formatter class for a
# known name (normalizing Symbol vs String), and raising Gem::CommandLineError
# for an unknown format. The raise is the registry's internal safety net -- the
# audit command validates --format before calling .for -- so it is exercised
# here rather than through the command.

class TestGemAuditFormatter < Gem::TestCase
  def test_for_returns_registered_text_formatter
    assert_equal Gem::Audit::Formatter::Text, Gem::Audit::Formatter.for("text")
  end

  def test_for_returns_registered_json_formatter
    assert_equal Gem::Audit::Formatter::JSON, Gem::Audit::Formatter.for("json")
  end

  def test_for_normalizes_symbol_names_to_strings
    assert_equal Gem::Audit::Formatter::JSON, Gem::Audit::Formatter.for(:json)
  end

  def test_for_unknown_format_raises_command_line_error
    error = assert_raise Gem::CommandLineError do
      Gem::Audit::Formatter.for("nope")
    end

    assert_equal "unknown audit format: nope", error.message
  end

  def test_fetch_is_an_alias_for_for
    assert_equal Gem::Audit::Formatter::Text, Gem::Audit::Formatter.fetch("text")
  end
end
