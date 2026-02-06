# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/rdoc_command"

class TestGemCommandsRdocCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::RdocCommand.new
  end

  def test_initialize
    assert_kind_of Gem::Command, @cmd
    assert_equal "rdoc", @cmd.command
    assert_match(/generates rdoc/i, @cmd.summary)
  end

  def test_command_name
    cmd = Gem::Commands::RdocCommand.new
    assert_equal "rdoc", cmd.command
    assert_equal "gem rdoc", cmd.program_name
  end

  def test_default_options_include_ri
    cmd = Gem::Commands::RdocCommand.new
    assert_equal true, cmd.options[:include_ri]
    assert cmd.options[:include_ri], "Expected include_ri to default to true"
  end

  def test_default_options_exclude_rdoc
    cmd = Gem::Commands::RdocCommand.new
    assert_equal false, cmd.options[:include_rdoc]
    refute cmd.options[:include_rdoc], "Expected include_rdoc to default to false"
  end

  def test_default_options_no_overwrite
    cmd = Gem::Commands::RdocCommand.new
    assert_equal false, cmd.options[:overwrite]
    refute cmd.options[:overwrite], "Expected overwrite to default to false"
  end

  def test_handle_options_all
    @cmd.handle_options %w[--all]

    assert @cmd.options[:all], "Expected --all to set options[:all] to true"
    assert_equal true, @cmd.options[:all]
  end

  def test_handle_options_rdoc
    @cmd.handle_options %w[--rdoc]

    assert_equal true, @cmd.options[:include_rdoc]
    assert @cmd.options[:include_rdoc], "Expected --rdoc to set include_rdoc to true"
  end

  def test_handle_options_no_ri
    @cmd.handle_options %w[--no-ri]

    assert_equal false, @cmd.options[:include_ri]
    refute @cmd.options[:include_ri], "Expected --no-ri to set include_ri to false"
  end

  def test_handle_options_overwrite
    @cmd.handle_options %w[--overwrite]

    assert_equal true, @cmd.options[:overwrite]
    assert @cmd.options[:overwrite], "Expected --overwrite to set overwrite to true"
  end

  def test_arguments
    result = @cmd.arguments

    assert_kind_of String, result
    assert_match(/GEMNAME/, result)
  end

  def test_defaults_str
    result = @cmd.defaults_str

    assert_match(/--ri/, result)
    assert_match(/--no-overwrite/, result)
  end

  def test_description
    result = @cmd.description

    assert_match(/rdoc/, result)
    assert_match(/rubygems plugins/, result)
  end

  def test_usage
    result = @cmd.usage

    assert_match(/gem rdoc/, result)
    assert_kind_of String, result
  end

  def test_execute_no_matching_gems
    # Use --all with an empty gem home so Gem::Specification.to_a returns []
    # and the production code hits the "No matching gems found" error path
    @cmd.options[:all] = true
    util_clear_gems

    use_ui @ui do
      assert_raise Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    assert_match(/no matching gems found/i, @ui.error)
    assert @ui.terminated?, "Expected interaction to be terminated"
  end

  def test_execute_with_installed_gem
    # Use quick_gem to register a spec without building a .gem file.
    # quick_gem writes the spec into @gemhome and resets the spec index.
    spec = quick_gem "rdoc_test_gem", "1.0"

    @cmd.options[:args] = %w[rdoc_test_gem]
    @cmd.options[:include_ri] = false
    @cmd.options[:include_rdoc] = false

    rdoc_generated = false
    rdoc_force_value = nil
    rdoc_spec_received = nil

    # Create a lightweight stand-in for Gem::RDoc that records whether
    # the production execute path instantiates and calls generate.
    # Only the external doc-generation I/O is replaced — the command
    # under test (RdocCommand#execute) runs its real code path.
    mock_rdoc_class = Class.new do
      attr_accessor :force

      define_method(:initialize) do |s, _include_rdoc, _include_ri|
        rdoc_spec_received = s
      end

      define_method(:generate) do
        rdoc_generated = true
        rdoc_force_value = force
      end
    end

    original_rdoc = nil
    rdoc_const_defined = Gem.const_defined?(:RDoc, false)

    if rdoc_const_defined
      original_rdoc = Gem::RDoc
      Gem.send(:remove_const, :RDoc)
    end

    Gem.const_set(:RDoc, mock_rdoc_class)

    begin
      use_ui @ui do
        @cmd.execute
      end

      assert rdoc_generated, "Expected Gem::RDoc#generate to be called"
      assert_equal spec, rdoc_spec_received
    ensure
      Gem.send(:remove_const, :RDoc)
      Gem.const_set(:RDoc, original_rdoc) if original_rdoc
    end
  end
end
