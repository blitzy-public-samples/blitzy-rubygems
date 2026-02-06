# frozen_string_literal: true

require "spec_helper"
require "bundler/match_remote_metadata"

RSpec.describe Bundler::MatchRemoteMetadata do
  # Lightweight test class that includes the production MatchRemoteMetadata
  # module. Provides a controllable _remote_specification accessor so that
  # FetchMetadata's lazy-fetching behavior can be exercised with controlled
  # doubles. No business logic is reimplemented — this class is pure
  # test-setup scaffolding for invoking real production methods.
  let(:test_class) do
    Class.new do
      include Bundler::MatchRemoteMetadata

      attr_accessor :remote_spec, :required_ruby_version, :required_rubygems_version

      def initialize(remote_spec:, deps: [])
        @remote_spec = remote_spec
        @deps = deps
        # Deliberately leave @required_ruby_version and @required_rubygems_version
        # unset so FetchMetadata's lazy initialization from _remote_specification
        # is exercised on first call to matches_current_ruby?/matches_current_rubygems?.
      end

      def _remote_specification
        @remote_spec
      end

      def runtime_dependencies
        @deps
      end
    end
  end

  # Helper to build a remote spec double with controlled version requirements.
  # Only external dependency doubles are created — the module methods under
  # test are never stubbed.
  let(:default_remote_spec) do
    double("remote_spec",
      required_ruby_version: Gem::Requirement.default,
      required_rubygems_version: Gem::Requirement.default)
  end

  describe "module composition" do
    it "includes MatchMetadata in the ancestor chain" do
      ancestors = Bundler::MatchRemoteMetadata.ancestors
      expect(ancestors).to include(Bundler::MatchMetadata)
      expect(test_class.ancestors).to include(Bundler::MatchMetadata)
    end

    it "prepends FetchMetadata in the ancestor chain" do
      ancestors = Bundler::MatchRemoteMetadata.ancestors
      expect(ancestors).to include(Bundler::FetchMetadata)
      fetch_idx = ancestors.index(Bundler::FetchMetadata)
      match_idx = ancestors.index(Bundler::MatchMetadata)
      expect(fetch_idx).to be < match_idx
    end

    it "responds to all MatchMetadata interface methods" do
      obj = test_class.new(remote_spec: default_remote_spec)
      expect(obj).to respond_to(:matches_current_ruby?)
      expect(obj).to respond_to(:matches_current_rubygems?)
      expect(obj).to respond_to(:matches_current_metadata?)
    end
  end

  describe "#matches_current_ruby?" do
    context "when required_ruby_version is not yet set" do
      it "fetches required_ruby_version from _remote_specification" do
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.new(">= 0"),
          required_rubygems_version: Gem::Requirement.default)
        obj = test_class.new(remote_spec: remote_spec)

        result = obj.matches_current_ruby?

        expect(result).to be true
        expect(obj.required_ruby_version).to eq(Gem::Requirement.new(">= 0"))
      end
    end

    context "when remote spec returns nil for required_ruby_version" do
      it "falls back to Gem::Requirement.default" do
        remote_spec = double("remote_spec",
          required_ruby_version: nil,
          required_rubygems_version: Gem::Requirement.default)
        obj = test_class.new(remote_spec: remote_spec)

        result = obj.matches_current_ruby?

        expect(result).to be true
        expect(obj.required_ruby_version).to eq(Gem::Requirement.default)
      end
    end

    context "when the remote spec requires an impossibly high Ruby version" do
      it "delegates to MatchMetadata#matches_current_ruby? which returns false" do
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.new(">= 99.0.0"),
          required_rubygems_version: Gem::Requirement.default)
        obj = test_class.new(remote_spec: remote_spec)

        expect(obj.matches_current_ruby?).to be false
        expect(obj.required_ruby_version).to eq(Gem::Requirement.new(">= 99.0.0"))
      end
    end

    context "when required_ruby_version is already cached" do
      it "does not re-fetch from remote spec on subsequent calls" do
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.new(">= 0"),
          required_rubygems_version: Gem::Requirement.default)
        obj = test_class.new(remote_spec: remote_spec)

        # First call fetches and caches @required_ruby_version
        obj.matches_current_ruby?

        # Override the cached value to an impossible requirement
        obj.required_ruby_version = Gem::Requirement.new(">= 99.0.0")

        # Subsequent call uses cached value, proving no re-fetch occurs
        expect(obj.matches_current_ruby?).to be false
        expect(obj.required_ruby_version).to eq(Gem::Requirement.new(">= 99.0.0"))
      end
    end

    context "with exact version match requirement" do
      it "matches only when current Ruby version is exactly the required version" do
        current_ruby = Gem.ruby_version.to_s
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.new("= #{current_ruby}"),
          required_rubygems_version: Gem::Requirement.default)
        obj = test_class.new(remote_spec: remote_spec)

        expect(obj.matches_current_ruby?).to be true
        expect(obj.required_ruby_version).to eq(Gem::Requirement.new("= #{current_ruby}"))
      end
    end
  end

  describe "#matches_current_rubygems?" do
    context "when required_rubygems_version is not yet set" do
      it "fetches required_rubygems_version from _remote_specification" do
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.default,
          required_rubygems_version: Gem::Requirement.new(">= 0"))
        obj = test_class.new(remote_spec: remote_spec)

        result = obj.matches_current_rubygems?

        expect(result).to be true
        expect(obj.required_rubygems_version).to eq(Gem::Requirement.new(">= 0"))
      end
    end

    context "when remote spec returns nil for required_rubygems_version" do
      it "falls back to Gem::Requirement.default" do
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.default,
          required_rubygems_version: nil)
        obj = test_class.new(remote_spec: remote_spec)

        result = obj.matches_current_rubygems?

        expect(result).to be true
        expect(obj.required_rubygems_version).to eq(Gem::Requirement.default)
      end
    end

    context "when the remote spec requires an impossibly high RubyGems version" do
      it "delegates to MatchMetadata#matches_current_rubygems? which returns false" do
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.default,
          required_rubygems_version: Gem::Requirement.new(">= 99.0.0"))
        obj = test_class.new(remote_spec: remote_spec)

        expect(obj.matches_current_rubygems?).to be false
        expect(obj.required_rubygems_version).to eq(Gem::Requirement.new(">= 99.0.0"))
      end
    end

    context "when required_rubygems_version is already cached" do
      it "does not re-fetch from remote spec on subsequent calls" do
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.default,
          required_rubygems_version: Gem::Requirement.new(">= 0"))
        obj = test_class.new(remote_spec: remote_spec)

        # First call fetches and caches @required_rubygems_version
        obj.matches_current_rubygems?

        # Override the cached value to an impossible requirement
        obj.required_rubygems_version = Gem::Requirement.new(">= 99.0.0")

        # Subsequent call uses cached value, proving no re-fetch occurs
        expect(obj.matches_current_rubygems?).to be false
        expect(obj.required_rubygems_version).to eq(Gem::Requirement.new(">= 99.0.0"))
      end
    end

    context "with exact version match requirement" do
      it "matches only when current RubyGems version is exactly the required version" do
        current_rubygems = Gem.rubygems_version.to_s
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.default,
          required_rubygems_version: Gem::Requirement.new("= #{current_rubygems}"))
        obj = test_class.new(remote_spec: remote_spec)

        expect(obj.matches_current_rubygems?).to be true
        expect(obj.required_rubygems_version).to eq(Gem::Requirement.new("= #{current_rubygems}"))
      end
    end
  end

  describe "#matches_current_metadata?" do
    context "when both remote Ruby and RubyGems versions are satisfied" do
      it "returns true" do
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.new(">= 0"),
          required_rubygems_version: Gem::Requirement.new(">= 0"))
        obj = test_class.new(remote_spec: remote_spec)

        expect(obj.matches_current_metadata?).to be true
        expect(obj.matches_current_ruby?).to be true
        expect(obj.matches_current_rubygems?).to be true
      end
    end

    context "when remote Ruby version requirement is not satisfied" do
      it "returns false" do
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.new(">= 99.0.0"),
          required_rubygems_version: Gem::Requirement.new(">= 0"))
        obj = test_class.new(remote_spec: remote_spec)

        expect(obj.matches_current_metadata?).to be false
        expect(obj.matches_current_ruby?).to be false
      end
    end

    context "when remote RubyGems version requirement is not satisfied" do
      it "returns false" do
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.new(">= 0"),
          required_rubygems_version: Gem::Requirement.new(">= 99.0.0"))
        obj = test_class.new(remote_spec: remote_spec)

        expect(obj.matches_current_metadata?).to be false
        expect(obj.matches_current_rubygems?).to be false
      end
    end

    context "when neither Ruby nor RubyGems version requirement is satisfied" do
      it "returns false" do
        remote_spec = double("remote_spec",
          required_ruby_version: Gem::Requirement.new(">= 99.0.0"),
          required_rubygems_version: Gem::Requirement.new(">= 99.0.0"))
        obj = test_class.new(remote_spec: remote_spec)

        expect(obj.matches_current_metadata?).to be false
        expect(obj.matches_current_ruby?).to be false
      end
    end

    context "when remote spec returns nil for both version requirements" do
      it "returns true using Gem::Requirement.default fallback for both" do
        remote_spec = double("remote_spec",
          required_ruby_version: nil,
          required_rubygems_version: nil)
        obj = test_class.new(remote_spec: remote_spec)

        expect(obj.matches_current_metadata?).to be true
        expect(obj.required_ruby_version).to eq(Gem::Requirement.default)
        expect(obj.required_rubygems_version).to eq(Gem::Requirement.default)
      end
    end
  end

  context "version filtering" do
    it "correctly applies pessimistic version constraint from remote spec" do
      current_ruby = Gem.ruby_version
      major = current_ruby.segments[0]
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new("~> #{major}.0"),
        required_rubygems_version: Gem::Requirement.new(">= 0"))
      obj = test_class.new(remote_spec: remote_spec)

      expect(obj.matches_current_ruby?).to be true
      expect(obj.matches_current_metadata?).to be true
    end

    it "rejects a spec when the ruby version requirement is strictly below current" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new("< 1.0"),
        required_rubygems_version: Gem::Requirement.new(">= 0"))
      obj = test_class.new(remote_spec: remote_spec)

      expect(obj.matches_current_ruby?).to be false
      expect(obj.matches_current_metadata?).to be false
    end

    it "rejects a spec when the rubygems version requirement is strictly below current" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 0"),
        required_rubygems_version: Gem::Requirement.new("< 1.0"))
      obj = test_class.new(remote_spec: remote_spec)

      expect(obj.matches_current_rubygems?).to be false
      expect(obj.matches_current_metadata?).to be false
    end

    it "accepts a spec with multiple version constraints that the current Ruby satisfies" do
      current_ruby = Gem.ruby_version
      major = current_ruby.segments[0]
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= #{major}.0", "< #{major + 1}.0"),
        required_rubygems_version: Gem::Requirement.new(">= 0"))
      obj = test_class.new(remote_spec: remote_spec)

      expect(obj.matches_current_ruby?).to be true
      expect(obj.matches_current_metadata?).to be true
    end

    it "rejects a spec with combined constraints that exclude the current Ruby" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 99.0.0", "< 100.0.0"),
        required_rubygems_version: Gem::Requirement.new(">= 0"))
      obj = test_class.new(remote_spec: remote_spec)

      expect(obj.matches_current_ruby?).to be false
      expect(obj.matches_current_metadata?).to be false
    end
  end

  context "platform requirements" do
    it "matches metadata when remote spec has broad platform-agnostic requirements" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.default,
        required_rubygems_version: Gem::Requirement.default)
      obj = test_class.new(remote_spec: remote_spec)

      expect(obj.matches_current_metadata?).to be true
      expect(obj.matches_current_ruby?).to be true
      expect(obj.matches_current_rubygems?).to be true
    end

    it "matches metadata when remote spec targets the current Ruby major version" do
      current_ruby = Gem.ruby_version
      major = current_ruby.segments[0]
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= #{major}.0.0"),
        required_rubygems_version: Gem::Requirement.new(">= 0"))
      obj = test_class.new(remote_spec: remote_spec)

      expect(obj.matches_current_metadata?).to be true
      expect(obj.required_ruby_version).to eq(Gem::Requirement.new(">= #{major}.0.0"))
    end

    it "rejects metadata when remote spec targets an incompatible Ruby version range" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new("~> 1.8"),
        required_rubygems_version: Gem::Requirement.new(">= 0"))
      obj = test_class.new(remote_spec: remote_spec)

      expect(obj.matches_current_metadata?).to be false
      expect(obj.matches_current_ruby?).to be false
    end

    it "applies both ruby and rubygems version constraints for platform compatibility" do
      current_ruby = Gem.ruby_version.to_s
      current_rubygems = Gem.rubygems_version.to_s
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new("= #{current_ruby}"),
        required_rubygems_version: Gem::Requirement.new("= #{current_rubygems}"))
      obj = test_class.new(remote_spec: remote_spec)

      expect(obj.matches_current_metadata?).to be true
      expect(obj.matches_current_ruby?).to be true
      expect(obj.matches_current_rubygems?).to be true
    end

    it "rejects when ruby matches but rubygems does not for platform requirements" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 0"),
        required_rubygems_version: Gem::Requirement.new("~> 0.1"))
      obj = test_class.new(remote_spec: remote_spec)

      expect(obj.matches_current_ruby?).to be true
      expect(obj.matches_current_rubygems?).to be false
      expect(obj.matches_current_metadata?).to be false
    end
  end

  describe "inherited MatchMetadata methods" do
    it "exposes expanded_dependencies through the module chain" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 2.0"),
        required_rubygems_version: Gem::Requirement.new(">= 1.0"))
      obj = test_class.new(remote_spec: remote_spec)

      # Trigger lazy initialization of version requirements
      obj.matches_current_metadata?

      result = obj.expanded_dependencies
      expect(result).to be_a(Array)
      names = result.map(&:name)
      expect(names).to include("Ruby\0")
      expect(names).to include("RubyGems\0")
    end

    it "exposes metadata_dependency through the module chain" do
      obj = test_class.new(remote_spec: default_remote_spec)

      dep = obj.metadata_dependency("Ruby", Gem::Requirement.new(">= 2.0"))
      expect(dep).to be_a(Gem::Dependency)
      expect(dep.name).to eq("Ruby\0")
    end

    it "returns nil from metadata_dependency for nil requirement" do
      obj = test_class.new(remote_spec: default_remote_spec)

      result = obj.metadata_dependency("Ruby", nil)
      expect(result).to be_nil
      expect(obj.metadata_dependency("RubyGems", nil)).to be_nil
    end

    it "returns nil from metadata_dependency for default (none?) requirement" do
      obj = test_class.new(remote_spec: default_remote_spec)

      result = obj.metadata_dependency("Ruby", Gem::Requirement.default)
      expect(result).to be_nil
      expect(obj.metadata_dependency("RubyGems", Gem::Requirement.default)).to be_nil
    end

    it "includes runtime dependencies in expanded_dependencies" do
      dep = Gem::Dependency.new("somegem", ">= 1.0")
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 2.0"),
        required_rubygems_version: Gem::Requirement.new(">= 1.0"))
      obj = test_class.new(remote_spec: remote_spec, deps: [dep])

      # Trigger lazy initialization
      obj.matches_current_metadata?

      result = obj.expanded_dependencies
      expect(result.length).to be >= 3
      expect(result.first.name).to eq("somegem")
    end
  end
end
