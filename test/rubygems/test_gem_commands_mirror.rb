# frozen_string_literal: true

require_relative "helper"
require "rubygems/commands/mirror_command"

class TestGemCommandsMirrorCommand < Gem::TestCase
  def setup
    super

    @cmd = Gem::Commands::MirrorCommand.new
  end

  def test_execute
    use_ui @ui do
      @cmd.execute
    end

    assert_match(/Install the rubygems-mirror/i, @ui.error)
  end

  def test_mirror_command_description
    description = @cmd.description

    assert_kind_of String, description
    assert_match(/rubygems-mirror/, description)
  end

  def test_mirror_command_name
    assert_equal "mirror", @cmd.command
    assert_match(/Mirror/, @cmd.summary)
  end

  def test_mirror_command_arguments
    arguments = @cmd.arguments
    usage = @cmd.usage

    assert_kind_of String, arguments
    assert_kind_of String, usage
  end

  def test_execute_outputs_error
    use_ui @ui do
      @cmd.execute
    end

    assert_match(/Install the rubygems-mirror gem for the mirror command/, @ui.error)
    assert_empty @ui.output
  end

  def test_mirror_command_initialize_without_rubygems_mirror
    cmd = Gem::Commands::MirrorCommand.new

    assert_kind_of Gem::Commands::MirrorCommand, cmd
    assert_kind_of Gem::Command, cmd
  end
end
