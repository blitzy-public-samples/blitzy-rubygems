# frozen_string_literal: true

require_relative "helper"
require "rubygems/deprecate"

class TestGemDeprecate < Gem::TestCase
  def setup
    super
    @original_skip = Gem::Deprecate.skip
    Gem::Deprecate.skip = false
  end

  def teardown
    Gem::Deprecate.skip = @original_skip
    super
  end

  ##
  # Verifies that the skip class-level getter returns false by default,
  # confirming deprecation warnings are enabled unless explicitly suppressed.

  def test_skip_default_value
    assert_equal false, @original_skip
    assert_equal false, Gem::Deprecate.skip
  end

  ##
  # Verifies that the skip= setter correctly changes the skip flag value
  # and that subsequent reads through the getter reflect the new state.

  def test_skip_setter_changes_value
    Gem::Deprecate.skip = true
    assert_equal true, Gem::Deprecate.skip

    Gem::Deprecate.skip = false
    assert_equal false, Gem::Deprecate.skip
  end

  ##
  # Verifies that skip_during temporarily sets skip to true for the duration
  # of the block and restores the original value after the block completes.

  def test_skip_during_temporarily_sets_skip_true
    assert_equal false, Gem::Deprecate.skip

    Gem::Deprecate.skip_during do
      assert_equal true, Gem::Deprecate.skip
    end

    assert_equal false, Gem::Deprecate.skip
  end

  ##
  # Verifies that skip_during restores the original skip value even when
  # an exception is raised inside the block, ensuring cleanup via ensure.

  def test_skip_during_restores_on_exception
    assert_equal false, Gem::Deprecate.skip

    assert_raise(RuntimeError) do
      Gem::Deprecate.skip_during do
        raise RuntimeError, "intentional test error"
      end
    end

    assert_equal false, Gem::Deprecate.skip
  end

  ##
  # Verifies that the deprecate method wraps an existing method and emits
  # a date-based deprecation warning containing the replacement method name
  # and the target removal date when the deprecated method is called.

  def test_deprecate_emits_date_based_warning_with_replacement
    klass = Class.new do
      extend Gem::Deprecate

      def old_method
        "result"
      end

      deprecate :old_method, "new_method", 2099, 3
    end

    _out, err = capture_output do
      klass.new.old_method
    end

    assert_match(/old_method is deprecated/, err)
    assert_match(/use new_method instead/, err)
    assert_match(/2099-03/, err)
  end

  ##
  # Verifies that the deprecate method with :none as the replacement emits
  # a deprecation warning indicating there is no replacement for the method.

  def test_deprecate_with_none_replacement_emits_no_replacement
    klass = Class.new do
      extend Gem::Deprecate

      def old_method
        "result"
      end

      deprecate :old_method, :none, 2099, 3
    end

    _out, err = capture_output do
      klass.new.old_method
    end

    assert_match(/old_method is deprecated/, err)
    assert_match(/with no replacement/, err)
  end

  ##
  # Verifies that the deprecate-wrapped method still executes the original
  # method body and returns its actual result to the caller.

  def test_deprecate_calls_original_method_and_returns_result
    klass = Class.new do
      extend Gem::Deprecate

      def old_method
        42
      end

      deprecate :old_method, "new_method", 2099, 3
    end

    result = nil
    capture_output do
      result = klass.new.old_method
    end

    assert_equal 42, result
    assert_not_nil result
  end

  ##
  # Verifies that rubygems_deprecate wraps a method and emits a version-based
  # deprecation warning containing the replacement name and a RubyGems version.

  def test_rubygems_deprecate_emits_version_based_warning
    klass = Class.new do
      extend Gem::Deprecate

      def old_method
        "result"
      end

      rubygems_deprecate :old_method, :new_method
    end

    _out, err = capture_output do
      klass.new.old_method
    end

    assert_match(/old_method is deprecated/, err)
    assert_match(/use new_method instead/, err)
    assert_match(/Rubygems/, err)
  end

  ##
  # Verifies that rubygems_deprecate with :none (default) replacement
  # emits a warning indicating there is no replacement for the method.

  def test_rubygems_deprecate_with_none_replacement
    klass = Class.new do
      extend Gem::Deprecate

      def old_method
        "result"
      end

      rubygems_deprecate :old_method
    end

    _out, err = capture_output do
      klass.new.old_method
    end

    assert_match(/old_method is deprecated/, err)
    assert_match(/with no replacement/, err)
  end

  ##
  # Verifies that rubygems_deprecate accepts a custom version parameter
  # and includes it in the emitted deprecation warning message.

  def test_rubygems_deprecate_with_custom_version
    klass = Class.new do
      extend Gem::Deprecate

      def old_method
        "result"
      end

      rubygems_deprecate :old_method, :new_method, Gem::Version.new("99.0")
    end

    _out, err = capture_output do
      klass.new.old_method
    end

    assert_match(/old_method is deprecated/, err)
    assert_match(/Rubygems 99\.0/, err)
  end

  ##
  # Verifies that the rubygems_deprecate-wrapped method still calls the
  # original method body and returns its result to the caller.

  def test_rubygems_deprecate_calls_original_method
    klass = Class.new do
      extend Gem::Deprecate

      def old_method
        "expected_value"
      end

      rubygems_deprecate :old_method, :new_method
    end

    result = nil
    capture_output do
      result = klass.new.old_method
    end

    assert_equal "expected_value", result
    assert_not_nil result
  end

  ##
  # Verifies that rubygems_deprecate_command defines a deprecated? method
  # on the command class that returns true.

  def test_rubygems_deprecate_command_defines_deprecated
    require "rubygems/command"

    cmd_class = Class.new(Gem::Command) do
      extend Gem::Deprecate
      rubygems_deprecate_command

      def execute; end
    end

    cmd = cmd_class.new("testdeprecated", "A test deprecated command")

    assert_respond_to cmd, :deprecated?
    assert_equal true, cmd.deprecated?
  end

  ##
  # Verifies that rubygems_deprecate_command defines a deprecation_warning
  # method that emits a warning through alert_warning containing the
  # command name and the target RubyGems version for removal.

  def test_rubygems_deprecate_command_defines_deprecation_warning
    require "rubygems/command"

    cmd_class = Class.new(Gem::Command) do
      extend Gem::Deprecate
      rubygems_deprecate_command

      def execute; end
    end

    cmd = cmd_class.new("testdeprecated", "A test deprecated command")

    assert_respond_to cmd, :deprecation_warning

    use_ui @ui do
      cmd.deprecation_warning
    end

    assert_match(/testdeprecated command is deprecated/, @ui.error)
    assert_match(/Rubygems/, @ui.error)
  end

  ##
  # Verifies that next_rubygems_major_version returns a Gem::Version instance
  # whose major segment is one greater than the current RubyGems major version.

  def test_next_rubygems_major_version_returns_bumped_version
    result = Gem::Deprecate.next_rubygems_major_version

    current_major = Gem.rubygems_version.segments.first

    assert_instance_of Gem::Version, result
    assert_equal current_major + 1, result.segments.first
  end
end
