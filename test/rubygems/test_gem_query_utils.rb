# frozen_string_literal: true

require_relative "helper"
require "rubygems/query_utils"

##
# Tests for the Gem::QueryUtils module exercised through a concrete
# Gem::Command subclass. Every test invokes real production methods
# from QueryUtils directly; no business logic is reimplemented.

class TestGemQueryUtils < Gem::TestCase
  ##
  # Minimal concrete Gem::Command subclass that includes Gem::QueryUtils
  # so we can test the module's methods in a real command context.

  class QueryUtilsTestCommand < Gem::Command
    include Gem::QueryUtils

    def initialize
      super "query_utils_test", "Test command for QueryUtils",
           domain: :local, details: false, versions: true,
           installed: nil, version: Gem::Requirement.default

      add_query_options
    end
  end

  def setup
    super
    @cmd = QueryUtilsTestCommand.new
    @stub_ui = Gem::MockGemUi.new
  end

  ##
  # Verifies that add_query_options registers --installed, --details,
  # --versions, --all, --exact, and --prerelease options on the command.

  def test_add_query_options
    @cmd.handle_options %w[--installed --details --versions --all --exact --prerelease]

    assert_equal true, @cmd.options[:installed]
    assert_equal true, @cmd.options[:details]
    assert_equal true, @cmd.options[:versions]
    assert_equal true, @cmd.options[:all]
    assert_equal true, @cmd.options[:exact]
    assert_equal true, @cmd.options[:prerelease]
  end

  ##
  # Verifies that defaults_str returns the expected default options string.

  def test_defaults_str
    result = @cmd.defaults_str

    assert_equal "--local --no-details --versions --no-installed", result
    assert_kind_of String, result
  end

  ##
  # Verifies that installed? returns true when a gem matching the name
  # and version requirement is present in the local specification store.

  def test_installed_true
    spec_fetcher do |fetcher|
      fetcher.spec "installed_check_gem", "1.0"
    end

    result = @cmd.send(:installed?, /installed_check_gem/)

    assert_equal true, result
    assert result, "Expected installed? to return truthy for an installed gem"
  end

  ##
  # Verifies that installed? returns false when no gem matches the
  # given name pattern in the local specification store.

  def test_installed_false
    result = @cmd.send(:installed?, /no_such_gem_xyz_abc_999/)

    assert_equal false, result
    refute result, "Expected installed? to return falsy for non-installed gem"
  end

  ##
  # Verifies that show_local_gems outputs matching local gem names
  # captured via Gem::MockGemUi.

  def test_show_local_gems
    spec_fetcher do |fetcher|
      fetcher.spec "local_show_gem", 1
      fetcher.spec "local_show_gem", 2
    end

    @cmd.options[:versions] = true

    use_ui @stub_ui do
      @cmd.send(:show_local_gems, /local_show_gem/)
    end

    assert_match(/local_show_gem/, @stub_ui.output)
    assert_empty @stub_ui.error
  end

  ##
  # Verifies that output_query_results formats spec tuples into
  # readable output containing gem name and version.

  def test_output_query_results
    spec = quick_gem "output_fmt_gem", "3.1"
    tuples = [[spec.name_tuple, spec]]

    @cmd.options[:versions] = true
    @cmd.options[:details] = false

    use_ui @stub_ui do
      @cmd.send(:output_query_results, tuples)
    end

    assert_match(/output_fmt_gem/, @stub_ui.output)
    assert_match(/3\.1/, @stub_ui.output)
  end

  ##
  # Verifies that specs_type returns :latest when neither --all
  # nor --prerelease is set and version is not specific.

  def test_specs_type_latest_by_default
    @cmd.options[:all] = false
    @cmd.options[:prerelease] = false
    @cmd.options[:version] = Gem::Requirement.default

    result = @cmd.send(:specs_type)

    assert_equal :latest, result
    assert_kind_of Symbol, result
  end

  ##
  # Verifies that specs_type returns :released when --all is set
  # but --prerelease is not.

  def test_specs_type_released_with_all
    @cmd.options[:all] = true
    @cmd.options[:prerelease] = false
    @cmd.options[:version] = Gem::Requirement.default

    result = @cmd.send(:specs_type)

    assert_equal :released, result
    assert_kind_of Symbol, result
  end

  ##
  # Verifies that specs_type returns :prerelease when --prerelease
  # is set but --all is not.

  def test_specs_type_prerelease
    @cmd.options[:all] = false
    @cmd.options[:prerelease] = true
    @cmd.options[:version] = Gem::Requirement.default

    result = @cmd.send(:specs_type)

    assert_equal :prerelease, result
    assert_kind_of Symbol, result
  end

  ##
  # Verifies that specs_type returns :complete when both --all
  # and --prerelease are set.

  def test_specs_type_complete_with_all_and_prerelease
    @cmd.options[:all] = true
    @cmd.options[:prerelease] = true
    @cmd.options[:version] = Gem::Requirement.default

    result = @cmd.send(:specs_type)

    assert_equal :complete, result
    assert_kind_of Symbol, result
  end

  ##
  # Verifies that check_installed_gems returns exit code 0
  # and outputs "true" when the gem is found.

  def test_check_installed_gems_found
    spec_fetcher do |fetcher|
      fetcher.spec "check_found_gem", "1.0"
    end

    @cmd.options[:args] = ["check_found_gem"]
    @cmd.options[:installed] = true
    @cmd.options[:version] = Gem::Requirement.default

    use_ui @stub_ui do
      exit_code = @cmd.send(:check_installed_gems, [/check_found_gem/])
      assert_equal 0, exit_code
    end

    assert_equal "true\n", @stub_ui.output
  end

  ##
  # Verifies that check_installed_gems returns exit code 1
  # and outputs "false" when the gem is not found.

  def test_check_installed_gems_missing
    @cmd.options[:args] = ["missing_gem_check"]
    @cmd.options[:installed] = true
    @cmd.options[:version] = Gem::Requirement.default

    use_ui @stub_ui do
      exit_code = @cmd.send(:check_installed_gems, [/missing_gem_check/])
      assert_equal 1, exit_code
    end

    assert_equal "false\n", @stub_ui.output
  end

  ##
  # Verifies that execute dispatches to show_gems, producing output
  # for matching local gems when no --installed flag is set.

  def test_execute_dispatches_to_show_gems
    spec_fetcher do |fetcher|
      fetcher.spec "dispatch_test_gem", 1
    end

    @cmd.options[:args] = ["dispatch_test_gem"]
    @cmd.options[:domain] = :local

    use_ui @stub_ui do
      @cmd.execute
    end

    assert_match(/dispatch_test_gem/, @stub_ui.output)
    assert_empty @stub_ui.error
  end

  ##
  # Verifies that display_header outputs the gem type header string
  # when verbose mode is on and output is a TTY.

  def test_display_header
    Gem.configuration.verbose = true

    use_ui @stub_ui do
      @cmd.send(:display_header, "LOCAL")
    end

    assert_match(/\*\*\* LOCAL GEMS \*\*\*/, @stub_ui.output)
    refute_empty @stub_ui.output
  end
end
