# frozen_string_literal: true

require_relative "helper"
require "rubygems/user_interaction"
require "rubygems/vendored_timeout"

class TestGemStreamUI < Gem::TestCase
  # increase timeout with RJIT for --jit-wait testing
  rjit_enabled = defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?
  SHORT_TIMEOUT = RUBY_ENGINE == "ruby" && !rjit_enabled ? 0.1 : 1.0

  module IsTty
    attr_accessor :tty

    def tty?
      @tty = true unless defined? @tty
      @tty
    end

    alias_method :isatty, :tty?

    def noecho
      yield self
    end
  end

  def setup
    super

    @cfg = Gem.configuration

    @in = StringIO.new
    @out = StringIO.new
    @err = StringIO.new

    @in.extend IsTty
    @out.extend IsTty

    @sui = Gem::StreamUI.new @in, @out, @err, true
  end

  def test_ask
    Gem::Timeout.timeout(5) do
      expected_answer = "Arthur, King of the Britons"
      @in.string = "#{expected_answer}\n"
      actual_answer = @sui.ask("What is your name?")
      assert_equal expected_answer, actual_answer
    end
  end

  def test_ask_no_tty
    @in.tty = false

    Gem::Timeout.timeout(SHORT_TIMEOUT) do
      answer = @sui.ask("what is your favorite color?")
      assert_nil answer
    end
  end

  def test_ask_for_password
    Gem::Timeout.timeout(5) do
      expected_answer = "Arthur, King of the Britons"
      @in.string = "#{expected_answer}\n"
      actual_answer = @sui.ask_for_password("What is your name?")
      assert_equal expected_answer, actual_answer
    end
  end

  def test_ask_for_password_no_tty
    @in.tty = false

    Gem::Timeout.timeout(SHORT_TIMEOUT) do
      answer = @sui.ask_for_password("what is the airspeed velocity of an unladen swallow?")
      assert_nil answer
    end
  end

  def test_ask_yes_no_no_tty_with_default
    @in.tty = false

    Gem::Timeout.timeout(SHORT_TIMEOUT) do
      answer = @sui.ask_yes_no("do coconuts migrate?", false)
      assert_equal false, answer

      answer = @sui.ask_yes_no("do coconuts migrate?", true)
      assert_equal true, answer
    end
  end

  def test_ask_yes_no_no_tty_without_default
    @in.tty = false

    Gem::Timeout.timeout(SHORT_TIMEOUT) do
      assert_raise(Gem::OperationNotSupportedError) do
        @sui.ask_yes_no("do coconuts migrate?")
      end
    end
  end

  def test_choose_from_list
    @in.puts "1"
    @in.rewind

    result = @sui.choose_from_list "which one?", %w[foo bar]

    assert_equal ["foo", 0], result
    assert_equal "which one?\n 1. foo\n 2. bar\n> ", @out.string
  end

  def test_choose_from_list_EOF
    result = @sui.choose_from_list "which one?", %w[foo bar]

    assert_equal [nil, nil], result
    assert_equal "which one?\n 1. foo\n 2. bar\n> ", @out.string
  end

  def test_choose_from_list_0
    @in.puts "0"
    @in.rewind

    result = @sui.choose_from_list "which one?", %w[foo bar]

    assert_equal [nil, nil], result
    assert_equal "which one?\n 1. foo\n 2. bar\n> ", @out.string
  end

  def test_choose_from_list_over
    @in.puts "3"
    @in.rewind

    result = @sui.choose_from_list "which one?", %w[foo bar]

    assert_equal [nil, nil], result
    assert_equal "which one?\n 1. foo\n 2. bar\n> ", @out.string
  end

  def test_choose_from_list_negative
    @in.puts "-1"
    @in.rewind

    result = @sui.choose_from_list "which one?", %w[foo bar]

    assert_equal [nil, nil], result
    assert_equal "which one?\n 1. foo\n 2. bar\n> ", @out.string
  end

  def test_progress_reporter_silent_nil
    @cfg.verbose = nil
    reporter = @sui.progress_reporter 10, "hi"
    assert_kind_of Gem::StreamUI::SilentProgressReporter, reporter
  end

  def test_progress_reporter_silent_false
    @cfg.verbose = false
    reporter = @sui.progress_reporter 10, "hi"
    assert_kind_of Gem::StreamUI::SilentProgressReporter, reporter
    assert_equal "", @out.string
  end

  def test_progress_reporter_simple
    @cfg.verbose = true
    reporter = @sui.progress_reporter 10, "hi"
    assert_kind_of Gem::StreamUI::SimpleProgressReporter, reporter
    assert_equal "hi\n", @out.string
  end

  def test_progress_reporter_verbose
    @cfg.verbose = 0
    reporter = @sui.progress_reporter 10, "hi"
    assert_kind_of Gem::StreamUI::VerboseProgressReporter, reporter
    assert_equal "hi\n", @out.string
  end

  def test_download_reporter_silent_nil
    @cfg.verbose = nil
    reporter = @sui.download_reporter
    reporter.fetch "a.gem", 1024
    assert_kind_of Gem::StreamUI::SilentDownloadReporter, reporter
    assert_equal "", @out.string
  end

  def test_download_reporter_silent_false
    @cfg.verbose = false
    reporter = @sui.download_reporter
    reporter.fetch "a.gem", 1024
    assert_kind_of Gem::StreamUI::SilentDownloadReporter, reporter
    assert_equal "", @out.string
  end

  def test_download_reporter_anything
    @cfg.verbose = 0
    reporter = @sui.download_reporter
    assert_kind_of Gem::StreamUI::ThreadedDownloadReporter, reporter
  end

  def test_threaded_download_reporter
    @cfg.verbose = true
    reporter = @sui.download_reporter
    reporter.fetch "a.gem", 1024
    assert_equal "Fetching a.gem\n", @out.string
  end

  def test_verbose_download_reporter_progress
    @cfg.verbose = true
    reporter = @sui.download_reporter
    reporter.fetch "a.gem", 1024
    reporter.update 512
    assert_equal "Fetching a.gem\n", @out.string
  end

  def test_verbose_download_reporter_progress_once
    @cfg.verbose = true
    reporter = @sui.download_reporter
    reporter.fetch "a.gem", 1024
    reporter.update 510
    reporter.update 512
    assert_equal "Fetching a.gem\n", @out.string
  end

  def test_verbose_download_reporter_progress_complete
    @cfg.verbose = true
    reporter = @sui.download_reporter
    reporter.fetch "a.gem", 1024
    reporter.update 510
    reporter.done
    assert_equal "Fetching a.gem\n", @out.string
  end

  def test_verbose_download_reporter_progress_nil_length
    @cfg.verbose = true
    reporter = @sui.download_reporter
    reporter.fetch "a.gem", nil
    reporter.update 1024
    reporter.done
    assert_equal "Fetching a.gem\n", @out.string
  end

  def test_verbose_download_reporter_progress_zero_length
    @cfg.verbose = true
    reporter = @sui.download_reporter
    reporter.fetch "a.gem", 0
    reporter.update 1024
    reporter.done
    assert_equal "Fetching a.gem\n", @out.string
  end

  def test_verbose_download_reporter_no_tty
    @out.tty = false

    @cfg.verbose = true
    reporter = @sui.download_reporter
    reporter.fetch "a.gem", 1024
    assert_equal "", @out.string
  end

  def test_alert
    @sui.alert("test message")
    assert_match(/INFO:/, @out.string)
    assert_match(/test message/, @out.string)
  end

  def test_alert_warning
    @sui.alert_warning("warning msg")
    assert_match(/WARNING:/, @err.string)
    assert_match(/warning msg/, @err.string)
  end

  def test_alert_error
    @sui.alert_error("error msg")
    assert_match(/ERROR:/, @err.string)
    assert_match(/error msg/, @err.string)
  end

  def test_say
    @sui.say("hello")
    assert_equal "hello\n", @out.string
  end

  def test_say_with_newline
    @sui.say("hello\n")
    assert_equal "hello\n", @out.string
  end

  def test_terminate_interaction_default
    e = assert_raise(Gem::SystemExitException) do
      @sui.terminate_interaction
    end
    assert_equal 0, e.exit_code
  end

  def test_terminate_interaction_with_status
    e = assert_raise(Gem::SystemExitException) do
      @sui.terminate_interaction(1)
    end
    assert_equal 1, e.exit_code
  end

  def test_verbose_and_quiet_modes
    @cfg.verbose = false
    @sui.say("quiet message")
    assert_equal "quiet message\n", @out.string

    @out.truncate(0)
    @out.rewind

    @cfg.verbose = true
    @sui.say("verbose message")
    assert_equal "verbose message\n", @out.string
  end

  def test_backtrace
    Gem.configuration.backtrace = true
    error = RuntimeError.new("test error")
    error.set_backtrace(["file.rb:1:in `method_a'", "file.rb:2:in `method_b'"])
    @sui.backtrace(error)
    assert_match(/method_a/, @err.string)
    assert_match(/method_b/, @err.string)
  end

  def test_ask_yes_no_yes
    Gem::Timeout.timeout(5) do
      @in.string = "y\n"
      result = @sui.ask_yes_no("proceed?")
      assert_equal true, result
    end
  end

  def test_ask_yes_no_no
    Gem::Timeout.timeout(5) do
      @in.string = "n\n"
      result = @sui.ask_yes_no("proceed?")
      assert_equal false, result
    end
  end
end
