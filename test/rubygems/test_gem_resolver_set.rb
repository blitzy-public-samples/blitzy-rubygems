# frozen_string_literal: true

require_relative "helper"

# Unit tests for the Gem::Resolver::Set base class.
# This class is the abstract foundation for all resolver sets used during
# dependency resolution. Tests verify initialization defaults, accessor
# behavior, the abstract find_all contract, and the no-op prefetch default.
#
# Every test method directly invokes real Gem::Resolver::Set production
# methods — no business logic is reimplemented in this file.

class TestGemResolverSet < Gem::TestCase
  def setup
    super

    @set = Gem::Resolver::Set.new
  end

  # Verifies that a freshly initialized Set has remote defaulting to true,
  # ensuring sets are network-enabled by default.
  def test_initialize_remote_default
    set = Gem::Resolver::Set.new

    assert_equal true, set.remote
    assert set.remote?, "Expected remote? to return true by default"
  end

  # Verifies that a freshly initialized Set has prerelease defaulting to false,
  # ensuring prerelease gems are excluded from resolution by default.
  def test_initialize_prerelease_default
    set = Gem::Resolver::Set.new

    assert_equal false, set.prerelease
    refute set.prerelease, "Expected prerelease to be false by default"
  end

  # Verifies that a freshly initialized Set starts with an empty errors array,
  # ready to accumulate resolution errors during use.
  def test_initialize_errors_default
    set = Gem::Resolver::Set.new

    assert_equal [], set.errors
    assert_empty set.errors
  end

  # Verifies that the remote= setter correctly changes the remote attribute
  # from its default true to a new value.
  def test_remote_setter
    assert_equal true, @set.remote

    @set.remote = false

    assert_equal false, @set.remote
    refute @set.remote?, "Expected remote? to return false after setting remote = false"
  end

  # Verifies that remote? returns the current remote value, confirming
  # the query method reflects the default state.
  def test_remote_query
    assert_equal true, @set.remote?
    assert @set.remote?, "Expected remote? to return true for default set"
  end

  # Verifies that remote? correctly returns false after the remote attribute
  # has been set to false via the setter.
  def test_remote_query_false
    @set.remote = false

    assert_equal false, @set.remote?
    refute @set.remote?, "Expected remote? to return false after disabling remote"
  end

  # Verifies that the prerelease= setter correctly changes the prerelease
  # attribute from its default false to true.
  def test_prerelease_setter
    assert_equal false, @set.prerelease

    @set.prerelease = true

    assert_equal true, @set.prerelease
  end

  # Verifies that the errors accessor allows appending error objects to the
  # errors array, accumulating resolution errors as expected.
  def test_errors_append
    assert_empty @set.errors

    error = Gem::DependencyError.new("test error")
    @set.errors << error

    assert_equal 1, @set.errors.length
    assert_equal error, @set.errors.first
  end

  # Verifies that calling find_all on the base Set class raises
  # NotImplementedError, enforcing the abstract contract that subclasses
  # must provide their own implementation.
  def test_find_all_raises_not_implemented
    dep_request = Gem::Resolver::DependencyRequest.new(
      dep("a", ">= 1"),
      nil
    )

    assert_raise NotImplementedError do
      @set.find_all(dep_request)
    end

    assert_raise NotImplementedError do
      @set.find_all(nil)
    end
  end

  # Verifies that the default prefetch implementation is a no-op that returns
  # nil, as the base class does not perform any pre-fetching.
  def test_prefetch_returns_nil
    result = @set.prefetch([])

    assert_nil result
    assert_empty @set.errors
  end

  # Verifies that prefetch gracefully accepts a populated reqs array without
  # raising an error, maintaining the no-op contract for the base class.
  def test_prefetch_with_reqs
    dep_request = Gem::Resolver::DependencyRequest.new(
      dep("a", ">= 1"),
      nil
    )

    result = @set.prefetch([dep_request])

    assert_nil result
    assert_empty @set.errors
  end
end
