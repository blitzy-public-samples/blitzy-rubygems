# frozen_string_literal: true

require_relative "helper"

class TestGemResolverSpecSpecification < Gem::TestCase
  def setup
    super

    @set = Gem::Resolver::CurrentSet.new

    @gem_spec = util_spec "my-gem", "2.0.1" do |s|
      s.add_dependency "dep-a", ">= 1.0"
      s.add_dependency "dep-b", "~> 3.0"
      s.required_ruby_version = ">= 3.0.0"
      s.required_rubygems_version = ">= 3.2.0"
      s.platform = Gem::Platform::RUBY
    end

    @source = Gem::Source.new(@gem_repo)

    @spec_spec = Gem::Resolver::SpecSpecification.new(@set, @gem_spec, @source)
  end

  def test_inherits_from_specification
    assert_kind_of Gem::Resolver::Specification, @spec_spec
    assert_equal true, Gem::Resolver::SpecSpecification.ancestors.include?(Gem::Resolver::Specification)
  end

  def test_initialize_stores_set_spec_source
    assert_same @set, @spec_spec.set
    assert_same @gem_spec, @spec_spec.spec
    assert_same @source, @spec_spec.source
  end

  def test_dependencies
    dependencies = @spec_spec.dependencies

    assert_equal 2, dependencies.length
    assert_equal "dep-a", dependencies[0].name
    assert_equal "dep-b", dependencies[1].name
  end

  def test_dependencies_empty
    spec_no_deps = util_spec "nodeps", "1.0"
    spec_spec_no_deps = Gem::Resolver::SpecSpecification.new(@set, spec_no_deps, @source)

    dependencies = spec_spec_no_deps.dependencies

    assert_empty dependencies
    assert_kind_of Array, dependencies
  end

  def test_required_ruby_version
    required_ruby = @spec_spec.required_ruby_version

    assert_equal @gem_spec.required_ruby_version, required_ruby
    assert_kind_of Gem::Requirement, required_ruby
  end

  def test_required_rubygems_version
    required_rg = @spec_spec.required_rubygems_version

    assert_equal @gem_spec.required_rubygems_version, required_rg
    assert_kind_of Gem::Requirement, required_rg
  end

  def test_full_name
    full_name = @spec_spec.full_name

    assert_equal "my-gem-2.0.1", full_name
    assert_equal "#{@gem_spec.name}-#{@gem_spec.version}", full_name
  end

  def test_name
    name = @spec_spec.name

    assert_equal "my-gem", name
    assert_equal @gem_spec.name, name
  end

  def test_version
    version = @spec_spec.version

    assert_equal Gem::Version.new("2.0.1"), version
    assert_equal @gem_spec.version, version
  end

  def test_platform
    platform = @spec_spec.platform

    assert_equal Gem::Platform::RUBY, platform
    assert_equal @gem_spec.platform, platform
  end

  def test_hash
    hash_value = @spec_spec.hash

    assert_equal @gem_spec.hash, hash_value
    assert_kind_of Integer, hash_value
  end

  def test_source_defaults_to_nil
    spec_no_source = Gem::Resolver::SpecSpecification.new(@set, @gem_spec)

    assert_nil spec_no_source.source
    assert_same @gem_spec, spec_no_source.spec
  end
end
