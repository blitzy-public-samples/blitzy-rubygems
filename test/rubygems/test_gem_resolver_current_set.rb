# frozen_string_literal: true

require_relative "helper"

class TestGemResolverCurrentSet < Gem::TestCase
  def setup
    super

    @set = Gem::Resolver::CurrentSet.new
  end

  # Verifies that CurrentSet is a subclass of the abstract Gem::Resolver::Set base class,
  # confirming it inherits the resolver set interface contract.
  def test_inherits_from_set
    assert_kind_of Gem::Resolver::Set, @set
    assert_equal Gem::Resolver::Set, Gem::Resolver::CurrentSet.superclass
  end

  # Verifies that CurrentSet responds to the find_all method required by the
  # resolver set interface, as well as the inherited prefetch method.
  def test_responds_to_find_all
    assert_respond_to @set, :find_all
    assert_respond_to @set, :prefetch
  end

  # Verifies that find_all returns the matching installed gem specification
  # when a gem matching the DependencyRequest is installed in the gem home.
  def test_find_all_returns_matching_installed_gem
    quick_gem "a", "1.0"

    a_dep = Gem::Resolver::DependencyRequest.new dep("a", ">= 0"), nil

    result = @set.find_all(a_dep)

    assert_kind_of Array, result
    assert_equal 1, result.length
    assert_equal "a", result.first.name
    assert_equal Gem::Version.new("1.0"), result.first.version
  end

  # Verifies that find_all returns an empty array when no installed gem
  # matches the name specified in the DependencyRequest.
  def test_find_all_returns_empty_for_unmatched
    a_dep = Gem::Resolver::DependencyRequest.new dep("nonexistent_gem_xyz", ">= 0"), nil

    result = @set.find_all(a_dep)

    assert_kind_of Array, result
    assert_empty result
  end

  # Verifies that find_all returns all installed versions of a gem
  # when multiple versions satisfy the DependencyRequest requirement.
  def test_find_all_returns_multiple_matches
    quick_gem "b", "1.0"
    quick_gem "b", "2.0"

    b_dep = Gem::Resolver::DependencyRequest.new dep("b", ">= 0"), nil

    result = @set.find_all(b_dep)

    assert_kind_of Array, result
    assert_equal 2, result.length

    version_strings = result.map {|s| s.version.to_s }.sort
    assert_equal %w[1.0 2.0], version_strings
  end

  # Verifies that the remote accessor defaults to true, inherited from
  # the Gem::Resolver::Set base class initializer.
  def test_inherits_remote_default
    assert_respond_to @set, :remote
    assert_equal true, @set.remote
    assert_predicate @set, :remote?
  end

  # Verifies that the prerelease accessor defaults to false, inherited from
  # the Gem::Resolver::Set base class initializer.
  def test_inherits_prerelease_default
    assert_respond_to @set, :prerelease
    assert_equal false, @set.prerelease
  end

  # Verifies that the errors accessor defaults to an empty array, inherited from
  # the Gem::Resolver::Set base class initializer.
  def test_inherits_errors_default
    assert_respond_to @set, :errors
    assert_equal [], @set.errors
  end
end
