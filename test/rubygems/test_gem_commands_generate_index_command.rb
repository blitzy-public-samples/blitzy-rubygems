# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/generate_index_command"

class TestGemCommandsGenerateIndexCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::GenerateIndexCommand.new
  end

  def test_initialize_command_name
    assert_equal "generate_index", @cmd.command
    assert_equal "gem generate_index", @cmd.program_name
  end

  def test_inherits_from_gem_command
    assert_kind_of Gem::Command, @cmd
    assert_instance_of Gem::Commands::GenerateIndexCommand, @cmd
  end

  def test_description
    description = @cmd.description

    assert_match(/rubygems-generate_index/, description)
    assert_match(/generate_index command has been moved/, description)
  end

  def test_execute_alerts_install_gem
    use_ui @ui do
      @cmd.execute
    end

    assert_match(/Install the rubygems-generate_index gem/, @ui.error)
    assert_match(/ERROR:/, @ui.error)
  end

  def test_summary
    summary = @cmd.summary

    assert_match(/gem server directory/, summary)
    assert_match(/rubygems-generate_index/, summary)
  end
end
