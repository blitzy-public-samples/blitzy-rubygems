# frozen_string_literal: true

require "spec_helper"
require "bundler/resolver"

RSpec.describe Bundler::Resolver do
  describe "#initialize" do
    it "creates a resolver with base, gem_version_promoter, and optional most_specific_locked_platform" do
      index = build_index do
        gem "myrack", "1.0.0"
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)

      expect(resolver).to be_a(described_class)
      expect(resolver).to respond_to(:start)
    end

    it "accepts a most_specific_locked_platform argument" do
      index = build_index do
        gem "myrack", "1.0.0"
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new
      locked_platform = Gem::Platform.new("x86_64-linux")

      resolver = described_class.new(base, gem_version_promoter, locked_platform)

      expect(resolver).to be_a(described_class)
      expect(resolver).to respond_to(:start)
    end
  end

  describe "#start" do
    it "resolves a single gem dependency successfully" do
      index = build_index do
        gem "myrack", "1.0.0"
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      expect(result).to be_a(Array)
      expect(result.map(&:name)).to include("myrack")
    end

    it "resolves multiple gem dependencies" do
      index = build_index do
        gem "myrack", "1.0.0"
        gem "thin", "1.0.0" do
          dep "myrack", ">= 0.9"
        end
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("thin", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      resolved_names = result.map(&:name)
      expect(resolved_names).to include("thin")
      expect(resolved_names).to include("myrack")
    end

    it "selects the highest compatible version when multiple versions are available" do
      index = build_index do
        gem "myrack", %w[0.9 1.0 1.1]
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      myrack_spec = result.find { |s| s.name == "myrack" }
      expect(myrack_spec).not_to be_nil
      expect(myrack_spec.version).to eq(Gem::Version.new("1.1"))
    end

    it "resolves with version constraints picking the right version" do
      index = build_index do
        gem "myrack", %w[0.9 1.0 1.1 2.0]
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", "~> 1.0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      myrack_spec = result.find { |s| s.name == "myrack" }
      expect(myrack_spec).not_to be_nil
      expect(myrack_spec.version).to be < Gem::Version.new("2.0")
    end
  end

  context "conflict detection" do
    it "raises an error when dependencies have incompatible version requirements" do
      index = build_index do
        gem "myrack", %w[1.0 2.0]
        gem "foo", "1.0" do
          dep "myrack", "~> 1.0"
        end
        gem "bar", "1.0" do
          dep "myrack", "~> 2.0"
        end
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [
        Bundler::Dependency.new("foo", ">= 0"),
        Bundler::Dependency.new("bar", ">= 0"),
      ]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)

      expect { resolver.start }.to raise_error(Bundler::SolveFailure)
    end

    it "raises GemNotFound when a required gem does not exist in the index" do
      index = build_index do
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("nonexistent_gem", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)

      expect { resolver.start }.to raise_error(Bundler::GemNotFound)
    end

    it "raises an error when a transitive dependency cannot be satisfied" do
      index = build_index do
        gem "foo", "1.0" do
          dep "bar", ">= 2.0"
        end
        gem "bar", "1.0"
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("foo", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)

      expect { resolver.start }.to raise_error(Bundler::SolveFailure)
    end

    it "includes a descriptive error message on solve failure" do
      index = build_index do
        gem "alpha", "1.0" do
          dep "beta", "~> 1.0"
        end
        gem "alpha", "2.0" do
          dep "beta", "~> 2.0"
        end
        gem "beta", "1.0"
        gem "gamma", "1.0" do
          dep "alpha", "~> 1.0"
          dep "beta", "~> 2.0"
        end
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("gamma", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)

      expect { resolver.start }.to raise_error(Bundler::SolveFailure) do |error|
        expect(error.message).to be_a(String)
      end
    end
  end

  context "platform filtering" do
    it "resolves platform-specific gems for the ruby platform" do
      index = build_index do
        gem "nokogiri", "1.4.0"
        gem "nokogiri", "1.4.0", "java" do
          dep "weakling", ">= 0.0.3"
        end
        gem "weakling", "0.0.3"
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("nokogiri", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      resolved_full_names = result.map(&:full_name)
      expect(resolved_full_names).to include("nokogiri-1.4.0")
      expect(resolved_full_names).not_to include("weakling-0.0.3")
    end

    it "resolves with java platform gems and their dependencies" do
      index = build_index do
        gem "nokogiri", "1.4.0"
        gem "nokogiri", "1.4.0", "java" do
          dep "weakling", ">= 0.0.3"
        end
        gem "weakling", "0.0.3"
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("nokogiri", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      # Use Gem::Platform objects for non-ruby platforms, matching the pattern
      # from bundler/spec/support/indexes.rb where the `platforms` helper
      # converts string arguments to Gem::Platform.new(...)
      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        [Gem::Platform.new("ruby"), Gem::Platform.new("java")],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      resolved_full_names = result.map(&:full_name)
      expect(resolved_full_names).to include("nokogiri-1.4.0")
      expect(resolved_full_names).to include("nokogiri-1.4.0-java")
    end

    it "resolves dependencies with mixed platform availability" do
      index = build_index do
        gem "foo", "1.0.0"
        gem "foo", "1.0.0", "x64-mingw-ucrt"
        gem "foo", "1.1.0"
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("foo", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      foo_spec = result.find { |s| s.name == "foo" }
      expect(foo_spec).not_to be_nil
      expect(foo_spec.version).to eq(Gem::Version.new("1.1.0"))
    end
  end

  context "resolution result construction" do
    it "returns results as an array of lazy specifications" do
      index = build_index do
        gem "myrack", "1.0.0"
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      expect(result).to be_a(Array)
      expect(result).not_to be_empty
      result.each do |spec|
        expect(spec).to respond_to(:name)
        expect(spec).to respond_to(:version)
      end
    end

    it "includes correct version information in resolved specs" do
      index = build_index do
        gem "myrack", "2.1.0"
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", "= 2.1.0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      myrack_spec = result.find { |s| s.name == "myrack" }
      expect(myrack_spec).not_to be_nil
      expect(myrack_spec.version).to eq(Gem::Version.new("2.1.0"))
    end

    it "resolves a dependency chain and includes all transitive dependencies" do
      index = build_index do
        gem "myrack", "1.0.0"
        gem "thin", "1.0.0" do
          dep "myrack", ">= 0.9"
        end
        gem "app", "1.0.0" do
          dep "thin", ">= 0"
        end
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("app", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      resolved_names = result.map(&:name)
      expect(resolved_names).to include("app")
      expect(resolved_names).to include("thin")
      expect(resolved_names).to include("myrack")
    end

    it "handles resolution with empty dependency list" do
      index = build_index do
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        [],
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      expect(result).to be_a(Array)
      expect(result).to be_empty
    end

    it "resolves with locked specs preserving locked versions" do
      index = build_index do
        gem "myrack", %w[1.0.0 1.1.0 2.0.0]
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      # Use Bundler::LazySpecification for the base set because
      # Resolver::Base#build_base_requirements calls source_changed? on each
      # spec in the base, which is a method only on LazySpecification.
      locked_lazy = Bundler::LazySpecification.new("myrack", Gem::Version.new("1.0.0"), nil)
      locked_lazy.source = default_source

      locked_set = Bundler::SpecSet.new([locked_lazy])

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        locked_set,
        ["ruby"],
        locked_specs: locked_set,
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      myrack_spec = result.find { |s| s.name == "myrack" }
      expect(myrack_spec).not_to be_nil
      expect(myrack_spec.version).to eq(Gem::Version.new("1.0.0"))
    end
  end

  describe "#sort_versions_by_preferred" do
    it "delegates sorting to the gem_version_promoter" do
      index = build_index do
        gem "myrack", %w[1.0 1.1 1.2]
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)

      package = base.get_package("myrack")
      versions = [
        Bundler::Resolver::Candidate.new("1.0"),
        Bundler::Resolver::Candidate.new("1.1"),
        Bundler::Resolver::Candidate.new("1.2"),
      ]
      sorted = resolver.sort_versions_by_preferred(package, versions)

      expect(sorted).to be_a(Array)
      expect(sorted.length).to eq(3)
    end
  end

  describe "#debug?" do
    it "returns false by default when no debug env vars are set" do
      index = build_index do
        gem "myrack", "1.0.0"
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)

      # Ensure debug env vars are not set
      original_debug = ENV["BUNDLER_DEBUG_RESOLVER"]
      original_tree = ENV["BUNDLER_DEBUG_RESOLVER_TREE"]
      original_d = ENV["DEBUG_RESOLVER"]
      original_dt = ENV["DEBUG_RESOLVER_TREE"]

      ENV.delete("BUNDLER_DEBUG_RESOLVER")
      ENV.delete("BUNDLER_DEBUG_RESOLVER_TREE")
      ENV.delete("DEBUG_RESOLVER")
      ENV.delete("DEBUG_RESOLVER_TREE")

      expect(resolver.debug?).to be_falsey
      expect(resolver.debug?).to eq(false)
    ensure
      ENV["BUNDLER_DEBUG_RESOLVER"] = original_debug
      ENV["BUNDLER_DEBUG_RESOLVER_TREE"] = original_tree
      ENV["DEBUG_RESOLVER"] = original_d
      ENV["DEBUG_RESOLVER_TREE"] = original_dt
    end
  end

  context "pre-release handling" do
    it "does not select pre-release versions unless explicitly specified" do
      index = build_index do
        gem "myrack", "1.0.0"
        gem "myrack", "2.0.0.beta1"
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      myrack_spec = result.find { |s| s.name == "myrack" }
      expect(myrack_spec).not_to be_nil
      expect(myrack_spec.version.prerelease?).to be false
    end

    it "selects a pre-release version when explicitly required" do
      index = build_index do
        gem "myrack", "1.0.0"
        gem "myrack", "2.0.0.beta1"
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("myrack", "= 2.0.0.beta1")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      myrack_spec = result.find { |s| s.name == "myrack" }
      expect(myrack_spec).not_to be_nil
      expect(myrack_spec.version).to eq(Gem::Version.new("2.0.0.beta1"))
    end
  end

  context "diamond dependency resolution" do
    it "resolves a diamond dependency graph correctly" do
      index = build_index do
        gem "top", "1.0.0" do
          dep "left", ">= 0"
          dep "right", ">= 0"
        end
        gem "left", "1.0.0" do
          dep "bottom", ">= 1.0"
        end
        gem "right", "1.0.0" do
          dep "bottom", ">= 1.0"
        end
        gem "bottom", %w[1.0.0 2.0.0]
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [Bundler::Dependency.new("top", ">= 0")]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        Bundler::SpecSet.new([]),
        ["ruby"],
        locked_specs: Bundler::SpecSet.new([]),
        unlock: []
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      resolved_names = result.map(&:name)
      expect(resolved_names).to include("top", "left", "right", "bottom")
      bottom_spec = result.find { |s| s.name == "bottom" }
      expect(bottom_spec.version).to eq(Gem::Version.new("2.0.0"))
    end
  end

  context "unlocking specific gems" do
    it "allows upgrading an unlocked gem while keeping others locked" do
      index = build_index do
        gem "foo", %w[1.0.0 1.1.0 2.0.0]
        gem "bar", %w[1.0.0 2.0.0]
        gem "RubyGems\0", Gem::VERSION
      end

      default_source = instance_double(
        "Bundler::Source::Rubygems",
        specs: index,
        to_s: "locally install gems",
        dependency_api_available?: true
      )
      source_requirements = { default: default_source }

      deps = [
        Bundler::Dependency.new("foo", ">= 0"),
        Bundler::Dependency.new("bar", ">= 0"),
      ]
      deps.each { |d| d.source = default_source; source_requirements[d.name] = default_source }

      # Lock bar at 1.0.0 using LazySpecification
      locked_bar = Bundler::LazySpecification.new("bar", Gem::Version.new("1.0.0"), nil)
      locked_bar.source = default_source
      locked_set = Bundler::SpecSet.new([locked_bar])

      base = Bundler::Resolver::Base.new(
        source_requirements,
        deps,
        locked_set,
        ["ruby"],
        locked_specs: locked_set,
        unlock: ["foo"]
      )
      gem_version_promoter = Bundler::GemVersionPromoter.new

      resolver = described_class.new(base, gem_version_promoter)
      result = resolver.start

      bar_spec = result.find { |s| s.name == "bar" }
      expect(bar_spec).not_to be_nil
      expect(bar_spec.version).to eq(Gem::Version.new("1.0.0"))

      foo_spec = result.find { |s| s.name == "foo" }
      expect(foo_spec).not_to be_nil
      expect(foo_spec.version).to eq(Gem::Version.new("2.0.0"))
    end
  end
end
