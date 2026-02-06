# frozen_string_literal: true

require_relative "helper"
require "rubygems/errors"

# Comprehensive unit tests for all Gem error classes defined in
# lib/rubygems/errors.rb. Each test method invokes real production
# error classes with controlled inputs and asserts on message strings,
# attributes, and class hierarchy. No business logic is reimplemented.
class TestGemErrors < Gem::TestCase
  # ----------------------------------------------------------------
  # Gem::LoadError
  # ----------------------------------------------------------------

  def test_load_error_inherits_from_load_error
    error = Gem::LoadError.new("unable to load gem")

    assert_kind_of ::LoadError, error
    assert_instance_of Gem::LoadError, error
  end

  def test_load_error_name_accessor
    error = Gem::LoadError.new("unable to load gem")

    assert_nil error.name

    error.name = "my_gem"
    assert_equal "my_gem", error.name
  end

  def test_load_error_requirement_accessor
    error = Gem::LoadError.new("unable to load gem")

    assert_nil error.requirement

    error.requirement = ">= 1.0"
    assert_equal ">= 1.0", error.requirement
  end

  # ----------------------------------------------------------------
  # Gem::MissingSpecError
  # ----------------------------------------------------------------

  def test_missing_spec_error_initialize
    error = Gem::MissingSpecError.new("my_gem", ">= 1.0")

    assert_equal "my_gem", error.name
    assert_equal ">= 1.0", error.requirement
    assert_kind_of Gem::LoadError, error
  end

  def test_missing_spec_error_message_includes_gem_path
    error = Gem::MissingSpecError.new("my_gem", ">= 1.0")
    message = error.message

    assert_match(/GEM_PATH=/, message)
    assert_match(/gem env/, message)
  end

  def test_missing_spec_error_message_includes_name_and_requirement
    error = Gem::MissingSpecError.new("some_gem", ">= 2.5")
    message = error.message

    assert_match(/Could not find/, message)
    assert_match(/some_gem/, message)
    assert_match(/>= 2\.5/, message)
  end

  def test_missing_spec_error_with_extra_message
    error = Gem::MissingSpecError.new("my_gem", ">= 1.0", "in Gemfile")
    message = error.message

    assert_match(/in Gemfile/, message)
    assert_match(/GEM_PATH=/, message)
  end

  # ----------------------------------------------------------------
  # Gem::MissingSpecVersionError
  # ----------------------------------------------------------------

  def test_missing_spec_version_error_initialize
    spec_a = util_spec("my_gem", "1.0")
    spec_b = util_spec("my_gem", "2.0")

    error = Gem::MissingSpecVersionError.new("my_gem", ">= 3.0", [spec_a, spec_b])

    assert_equal "my_gem", error.name
    assert_equal ">= 3.0", error.requirement
    assert_kind_of Gem::MissingSpecError, error
  end

  def test_missing_spec_version_error_message_includes_spec_names
    spec_a = util_spec("my_gem", "1.0")
    spec_b = util_spec("my_gem", "2.0")

    error = Gem::MissingSpecVersionError.new("my_gem", ">= 3.0", [spec_a, spec_b])
    message = error.message

    assert_match(/did find:/, message)
    assert_match(/my_gem-1\.0/, message)
    assert_match(/my_gem-2\.0/, message)
  end

  def test_missing_spec_version_error_specs_accessor
    spec_a = util_spec("my_gem", "1.0")
    spec_b = util_spec("my_gem", "2.0")
    specs = [spec_a, spec_b]

    error = Gem::MissingSpecVersionError.new("my_gem", ">= 3.0", specs)

    assert_equal specs, error.specs
    assert_equal 2, error.specs.size
  end

  # ----------------------------------------------------------------
  # Gem::ConflictError
  # ----------------------------------------------------------------

  def test_conflict_error_stores_target_and_conflicts
    target = util_spec("target_gem", "1.0")
    conflicting = util_spec("conflict_gem", "2.0")
    conflicts = { conflicting => [dep("target_gem", "< 1.0")] }

    error = Gem::ConflictError.new(target, conflicts)

    assert_equal target, error.target
    assert_equal conflicts, error.conflicts
  end

  def test_conflict_error_message_describes_conflict
    target = util_spec("target_gem", "1.0")
    conflicting = util_spec("conflict_gem", "2.0")
    conflicts = { conflicting => [dep("target_gem", "< 1.0")] }

    error = Gem::ConflictError.new(target, conflicts)
    message = error.message

    assert_match(/Unable to activate target_gem-1\.0/, message)
    assert_match(/conflict_gem-2\.0 conflicts with/, message)
  end

  def test_conflict_error_name_set_to_target_name
    target = util_spec("target_gem", "1.0")
    conflicting = util_spec("conflict_gem", "2.0")
    conflicts = { conflicting => [dep("target_gem", "< 1.0")] }

    error = Gem::ConflictError.new(target, conflicts)

    assert_equal "target_gem", error.name
    assert_kind_of Gem::LoadError, error
  end

  # ----------------------------------------------------------------
  # Gem::ErrorReason
  # ----------------------------------------------------------------

  def test_error_reason_instantiation
    reason = Gem::ErrorReason.new

    assert_instance_of Gem::ErrorReason, reason
    assert_kind_of Gem::ErrorReason, reason
  end

  # ----------------------------------------------------------------
  # Gem::PlatformMismatch
  # ----------------------------------------------------------------

  def test_platform_mismatch_stores_name_and_version
    mismatch = Gem::PlatformMismatch.new("my_gem", "1.0")

    assert_equal "my_gem", mismatch.name
    assert_equal "1.0", mismatch.version
  end

  def test_platform_mismatch_platforms_initially_empty
    mismatch = Gem::PlatformMismatch.new("my_gem", "1.0")

    assert_empty mismatch.platforms
    assert_kind_of Array, mismatch.platforms
  end

  def test_platform_mismatch_add_platform_appends
    mismatch = Gem::PlatformMismatch.new("my_gem", "1.0")

    mismatch.add_platform("java")
    assert_equal ["java"], mismatch.platforms

    mismatch.add_platform("x86-mingw32")
    assert_equal ["java", "x86-mingw32"], mismatch.platforms
  end

  def test_platform_mismatch_wordy_singular_platform
    mismatch = Gem::PlatformMismatch.new("my_gem", "1.0")
    mismatch.add_platform("java")

    result = mismatch.wordy

    assert_match(/Found my_gem \(1\.0\)/, result)
    assert_match(/but was for platform java/, result)
    refute_match(/platforms/, result)
  end

  def test_platform_mismatch_wordy_multiple_platforms
    mismatch = Gem::PlatformMismatch.new("my_gem", "1.0")
    mismatch.add_platform("java")
    mismatch.add_platform("x86-mingw32")

    result = mismatch.wordy

    assert_match(/Found my_gem \(1\.0\)/, result)
    assert_match(/platforms/, result)
    assert_match(/java/, result)
  end

  # ----------------------------------------------------------------
  # Gem::SourceFetchProblem
  # ----------------------------------------------------------------

  def test_source_fetch_problem_stores_source_and_error
    source = Gem::Source.new("http://gems.example.com")
    error  = RuntimeError.new("connection failed")

    problem = Gem::SourceFetchProblem.new(source, error)

    assert_equal source, problem.source
    assert_equal error, problem.error
  end

  def test_source_fetch_problem_wordy_description
    source = Gem::Source.new("http://gems.example.com")
    error  = RuntimeError.new("connection timed out")

    problem = Gem::SourceFetchProblem.new(source, error)
    result  = problem.wordy

    assert_match(/Unable to download data from/, result)
    assert_match(/connection timed out/, result)
  end

  def test_source_fetch_problem_exception_alias
    source = Gem::Source.new("http://gems.example.com")
    error  = RuntimeError.new("network error")

    problem = Gem::SourceFetchProblem.new(source, error)

    assert_equal error, problem.exception
    assert_same problem.error, problem.exception
  end
end
