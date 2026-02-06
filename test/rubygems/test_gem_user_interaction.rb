# frozen_string_literal: true

require_relative "helper"
require "rubygems/user_interaction"
require "stringio"

##
# Tests for Gem::UserInteraction module methods and Gem::DefaultUserInteraction
# class-level UI management. Each test invokes production code directly through
# a minimal host class and asserts on observable output and return values.

class TestGemUserInteraction < Gem::TestCase
  ##
  # Minimal host class that includes Gem::UserInteraction so the module methods
  # (alert, ask, say, verbose, etc.) can be exercised directly on an instance.
  # Contains no business logic — only the module inclusion.

  class UserInteractionHost
    include Gem::UserInteraction
  end

  def setup
    super
    @host = UserInteractionHost.new
  end

  ##
  # Verifies that #alert delegates to ui.alert and produces "INFO:" prefixed
  # output on the standard output stream with no error stream output.

  def test_alert_produces_output
    mock_ui = Gem::MockGemUi.new

    use_ui(mock_ui) do
      @host.alert("test alert message")
    end

    assert_match(/INFO:  test alert message/, mock_ui.output)
    assert_equal "", mock_ui.error
  end

  ##
  # Verifies that #alert_error delegates to ui.alert_error and writes
  # "ERROR:" prefixed output to the error stream, not standard output.

  def test_alert_error_writes_to_error_stream
    mock_ui = Gem::MockGemUi.new

    use_ui(mock_ui) do
      @host.alert_error("something went wrong")
    end

    assert_match(/ERROR:  something went wrong/, mock_ui.error)
    assert_equal "", mock_ui.output
  end

  ##
  # Verifies that #alert_warning delegates to ui.alert_warning and writes
  # "WARNING:" prefixed output to the error stream, not standard output.

  def test_alert_warning_writes_to_error_stream
    mock_ui = Gem::MockGemUi.new

    use_ui(mock_ui) do
      @host.alert_warning("be careful")
    end

    assert_match(/WARNING:  be careful/, mock_ui.error)
    assert_equal "", mock_ui.output
  end

  ##
  # Verifies that #ask delegates to ui.ask, prompts the user via the output
  # stream, and returns the input string provided by the user.

  def test_ask_returns_user_input
    mock_ui = Gem::MockGemUi.new("Arthur, King of the Britons\n")

    use_ui(mock_ui) do
      answer = @host.ask("What is your name?")
      assert_equal "Arthur, King of the Britons", answer
    end

    assert_match(/What is your name\?/, mock_ui.output)
  end

  ##
  # Verifies that #ask_yes_no delegates to ui.ask_yes_no with the default
  # parameter. When the user provides empty input (presses Enter), the
  # default value is returned.

  def test_ask_yes_no_with_default
    mock_ui = Gem::MockGemUi.new("\n")

    use_ui(mock_ui) do
      result = @host.ask_yes_no("Continue?", true)
      assert_equal true, result
    end

    assert_match(/Continue\?/, mock_ui.output)
  end

  ##
  # Verifies that #choose_from_list delegates to ui.choose_from_list and
  # returns the [item_name, item_index] pair for the user-selected option.
  # Index is zero-based while the user enters a one-based number.

  def test_choose_from_list_returns_pair
    mock_ui = Gem::MockGemUi.new("1\n")

    use_ui(mock_ui) do
      name, index = @host.choose_from_list("Pick one:", %w[alpha beta gamma])
      assert_equal "alpha", name
      assert_equal 0, index
    end
  end

  ##
  # Verifies that #say outputs the given statement string to the standard
  # output stream with a trailing newline.

  def test_say_outputs_statement
    mock_ui = Gem::MockGemUi.new

    use_ui(mock_ui) do
      @host.say("hello world")
    end

    assert_equal "hello world\n", mock_ui.output
    assert_equal "", mock_ui.error
  end

  ##
  # Verifies that #say with an empty string produces output containing only
  # a newline character (from the underlying puts call).

  def test_say_empty_string
    mock_ui = Gem::MockGemUi.new

    use_ui(mock_ui) do
      @host.say("")
    end

    assert_equal "\n", mock_ui.output
    assert_equal "", mock_ui.error
  end

  ##
  # Verifies that #terminate_interaction raises a SystemExit-derived exception
  # with the specified exit code. MockGemUi raises TermError (subclass of
  # SystemExit) for non-zero codes and SystemExitException for zero.

  def test_terminate_interaction_raises_system_exit
    mock_ui = Gem::MockGemUi.new

    use_ui(mock_ui) do
      error = assert_raise(Gem::MockGemUi::TermError) do
        @host.terminate_interaction(1)
      end
      assert_equal 1, error.exit_code
    end
  end

  ##
  # Verifies that #verbose outputs the message when Gem.configuration.really_verbose
  # returns true. Setting verbose to a numeric value (not true/false/nil) triggers
  # really_verbose mode.

  def test_verbose_outputs_when_really_verbose
    mock_ui = Gem::MockGemUi.new
    Gem.configuration.verbose = 1

    use_ui(mock_ui) do
      @host.verbose("detailed debug info")
    end

    assert_match(/detailed debug info/, mock_ui.output)
    assert_equal "", mock_ui.error
  ensure
    Gem.configuration.verbose = true
  end

  ##
  # Verifies that #verbose does NOT produce output when really_verbose is false.
  # Setting verbose = true means normal verbosity, which is NOT really_verbose.

  def test_verbose_silent_when_not_really_verbose
    mock_ui = Gem::MockGemUi.new
    Gem.configuration.verbose = true

    use_ui(mock_ui) do
      @host.verbose("should not appear")
    end

    assert_equal "", mock_ui.output
    assert_equal "", mock_ui.error
  end

  ##
  # Verifies that Gem::DefaultUserInteraction.ui returns a Gem::StreamUI
  # instance (or subclass) that responds to the standard UI methods.

  def test_default_user_interaction_ui_returns_instance
    result = Gem::DefaultUserInteraction.ui

    assert_kind_of Gem::StreamUI, result
    assert_respond_to result, :alert
  end

  ##
  # Verifies that Gem::DefaultUserInteraction.ui= replaces the default UI
  # and that the new UI is returned by both the class method and the
  # instance method on objects including the module.

  def test_default_user_interaction_ui_setter
    original = Gem::DefaultUserInteraction.ui
    new_ui = Gem::MockGemUi.new

    Gem::DefaultUserInteraction.ui = new_ui

    assert_same new_ui, Gem::DefaultUserInteraction.ui
    assert_same new_ui, @host.ui
  ensure
    Gem::DefaultUserInteraction.ui = original
  end

  ##
  # Verifies that Gem::DefaultUserInteraction.use_ui temporarily swaps the
  # UI for the duration of a block, making the temporary UI active inside
  # the block, then restores the original UI afterward.

  def test_default_user_interaction_use_ui_temporarily_swaps
    original = Gem::DefaultUserInteraction.ui
    out_stream = StringIO.new
    temp_ui = Gem::StreamUI.new(StringIO.new, out_stream, StringIO.new, false)

    Gem::DefaultUserInteraction.use_ui(temp_ui) do
      assert_same temp_ui, Gem::DefaultUserInteraction.ui
      @host.say("inside use_ui block")
    end

    assert_same original, Gem::DefaultUserInteraction.ui
    assert_equal "inside use_ui block\n", out_stream.string
  end

  ##
  # Verifies that use_ui restores the original UI even when the block raises
  # an exception, confirming the ensure-based cleanup in the production code.

  def test_use_ui_restores_on_exception
    original = Gem::DefaultUserInteraction.ui
    temp_ui = Gem::MockGemUi.new

    assert_raise(RuntimeError) do
      Gem::DefaultUserInteraction.use_ui(temp_ui) do
        raise RuntimeError, "simulated failure"
      end
    end

    assert_same original, Gem::DefaultUserInteraction.ui
    refute_same temp_ui, Gem::DefaultUserInteraction.ui
  end
end
