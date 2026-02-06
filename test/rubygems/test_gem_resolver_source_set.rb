# frozen_string_literal: true

require_relative "helper"

class TestGemResolverSourceSet < Gem::TestCase
  def setup
    super

    @source_set = Gem::Resolver::SourceSet.new
  end

  ##
  # Verifies that Gem::Resolver::SourceSet inherits from the abstract
  # Gem::Resolver::Set base class, gaining remote, prerelease, and errors
  # accessors along with the find_all and prefetch interface contract.

  def test_inherits_from_set
    assert_kind_of Gem::Resolver::Set, @source_set
    assert_respond_to @source_set, :find_all
    assert_respond_to @source_set, :prefetch
  end

  ##
  # Verifies that a freshly created SourceSet has empty internal link and
  # set hashes, meaning no gem-to-source associations exist yet.

  def test_initialize_empty_state
    ss = Gem::Resolver::SourceSet.new

    links = ss.instance_variable_get(:@links)
    sets  = ss.instance_variable_get(:@sets)

    assert_empty links
    assert_empty sets
    assert_instance_of Hash, links
  end

  ##
  # Verifies that add_source_gem stores the gem name to source URI
  # association in the internal links hash.

  def test_add_source_gem
    @source_set.add_source_gem("a", @gem_repo)

    links = @source_set.instance_variable_get(:@links)

    assert_equal @gem_repo, links["a"]
    assert_equal 1, links.size
  end

  ##
  # Verifies that find_all returns an empty array when no source has
  # been linked for the requested gem name.

  def test_find_all_unlinked_gem
    a_dep = dep("a", ">= 0")
    req   = Gem::Resolver::DependencyRequest.new(a_dep, nil)

    result = @source_set.find_all(req)

    assert_equal [], result
    assert_empty result
  end

  ##
  # Verifies that find_all delegates to the underlying dependency
  # resolver set when a source has been linked for the requested gem.
  # Uses Gem::FakeFetcher (via spec_fetcher) for network isolation.

  def test_find_all_linked_source
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
    end

    assert_instance_of Gem::FakeFetcher, @fetcher

    expected = util_spec("a", 1)

    @source_set.add_source_gem("a", @gem_repo)

    a_dep = dep("a", ">= 0")
    req   = Gem::Resolver::DependencyRequest.new(a_dep, nil)

    result = @source_set.find_all(req)

    refute_empty result
    assert_equal expected.name, result.first.name
    assert_equal expected.version, result.first.version
  end

  ##
  # Verifies that prefetch does not raise when given an empty array
  # of requests, and that no internal sets are created.

  def test_prefetch_empty
    @source_set.prefetch([])

    sets  = @source_set.instance_variable_get(:@sets)
    links = @source_set.instance_variable_get(:@links)

    assert_empty sets
    assert_empty links
  end

  ##
  # Verifies that prefetch iterates over linked dependency requests
  # and creates the underlying resolver set for matched sources.

  def test_prefetch_linked_requests
    spec_fetcher do |fetcher|
      fetcher.spec "a", 1
    end

    @source_set.add_source_gem("a", @gem_repo)

    a_dep = dep("a", ">= 0")
    req   = Gem::Resolver::DependencyRequest.new(a_dep, nil)

    @source_set.prefetch([req])

    sets = @source_set.instance_variable_get(:@sets)

    refute_empty sets
    assert_equal 1, sets.size
  end

  ##
  # Verifies that multiple add_source_gem calls for different gem names
  # each store their own independent name-to-source association.

  def test_multiple_add_source_gem
    source_a = "http://source-a.example.com/"
    source_b = "http://source-b.example.com/"

    @source_set.add_source_gem("a", source_a)
    @source_set.add_source_gem("b", source_b)

    links = @source_set.instance_variable_get(:@links)

    assert_equal 2, links.size
    assert_equal source_a, links["a"]
    assert_equal source_b, links["b"]
  end

  ##
  # Verifies that SourceSet inherits the default remote=true,
  # prerelease=false, and empty errors array from the base Set class.

  def test_inherits_remote_prerelease_defaults
    assert_equal true, @source_set.remote
    assert_equal false, @source_set.prerelease
    assert_empty @source_set.errors
  end
end
