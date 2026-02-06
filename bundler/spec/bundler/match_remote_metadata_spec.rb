# frozen_string_literal: true

require "spec_helper"
require "bundler/match_remote_metadata"

RSpec.describe Bundler::MatchRemoteMetadata do
  # Test class that includes MatchRemoteMetadata and provides a controllable
  # _remote_specification accessor. This allows testing the FetchMetadata
  # prepend behavior that lazily fetches required versions from the remote spec.
  let(:test_class) do
    Class.new do
      include Bundler::MatchRemoteMetadata

      attr_accessor :remote_spec, :required_ruby_version, :required_rubygems_version

      def initialize(remote_spec:, deps: [])
        @remote_spec = remote_spec
        @deps = deps
        # Do NOT set @required_ruby_version or @required_rubygems_version here
        # so that FetchMetadata's lazy initialization from _remote_specification
        # is exercised.
      end

      def _remote_specification
        @remote_spec
      end

      def runtime_dependencies
        @deps
      end
    end
  end

  describe "module composition" do
    it "includes MatchMetadata in the ancestor chain" do
      expect(Bundler::MatchRemoteMetadata.ancestors).to include(Bundler::MatchMetadata)
      expect(test_class.ancestors).to include(Bundler::MatchMetadata)
    end

    it "prepends FetchMetadata in the ancestor chain" do
      expect(Bundler::MatchRemoteMetadata.ancestors).to include(Bundler::FetchMetadata)
      # FetchMetadata should appear before MatchMetadata in the ancestors
      fetch_idx = Bundler::MatchRemoteMetadata.ancestors.index(Bundler::FetchMetadata)
      match_idx = Bundler::MatchRemoteMetadata.ancestors.index(Bundler::MatchMetadata)
      expect(fetch_idx).to be < match_idx
    end
  end

  describe "#matches_current_ruby?" do
    it "fetches required_ruby_version from _remote_specification when not already set" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 0"),
        required_rubygems_version: Gem::Requirement.default
      )
      obj = test_class.new(remote_spec: remote_spec)
      result = obj.matches_current_ruby?
      expect(result).to be true
      expect(obj.required_ruby_version).to eq(Gem::Requirement.new(">= 0"))
    end

    it "falls back to Gem::Requirement.default when remote spec returns nil" do
      remote_spec = double("remote_spec",
        required_ruby_version: nil,
        required_rubygems_version: Gem::Requirement.default
      )
      obj = test_class.new(remote_spec: remote_spec)
      result = obj.matches_current_ruby?
      expect(result).to be true
      expect(obj.required_ruby_version).to eq(Gem::Requirement.default)
    end

    it "delegates to MatchMetadata#matches_current_ruby? via super after setting requirement" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 99.0.0"),
        required_rubygems_version: Gem::Requirement.default
      )
      obj = test_class.new(remote_spec: remote_spec)
      # The actual version check is done by MatchMetadata#matches_current_ruby?
      # which checks @required_ruby_version.satisfied_by?(Gem.ruby_version)
      expect(obj.matches_current_ruby?).to be false
      expect(obj.required_ruby_version).to eq(Gem::Requirement.new(">= 99.0.0"))
    end

    it "does not re-fetch from remote spec once required_ruby_version is set" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 0"),
        required_rubygems_version: Gem::Requirement.default
      )
      obj = test_class.new(remote_spec: remote_spec)
      # First call fetches and sets @required_ruby_version
      obj.matches_current_ruby?
      # Manually override to verify subsequent calls don't refetch
      obj.required_ruby_version = Gem::Requirement.new(">= 99.0.0")
      expect(obj.matches_current_ruby?).to be false
      expect(obj.required_ruby_version).to eq(Gem::Requirement.new(">= 99.0.0"))
    end
  end

  describe "#matches_current_rubygems?" do
    it "fetches required_rubygems_version from _remote_specification when not already set" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.default,
        required_rubygems_version: Gem::Requirement.new(">= 0")
      )
      obj = test_class.new(remote_spec: remote_spec)
      result = obj.matches_current_rubygems?
      expect(result).to be true
      expect(obj.required_rubygems_version).to eq(Gem::Requirement.new(">= 0"))
    end

    it "falls back to Gem::Requirement.default when remote spec returns nil" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.default,
        required_rubygems_version: nil
      )
      obj = test_class.new(remote_spec: remote_spec)
      result = obj.matches_current_rubygems?
      expect(result).to be true
      expect(obj.required_rubygems_version).to eq(Gem::Requirement.default)
    end

    it "delegates to MatchMetadata#matches_current_rubygems? via super after setting requirement" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.default,
        required_rubygems_version: Gem::Requirement.new(">= 99.0.0")
      )
      obj = test_class.new(remote_spec: remote_spec)
      expect(obj.matches_current_rubygems?).to be false
      expect(obj.required_rubygems_version).to eq(Gem::Requirement.new(">= 99.0.0"))
    end
  end

  describe "#matches_current_metadata?" do
    it "returns true when both remote Ruby and RubyGems versions are satisfied" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 0"),
        required_rubygems_version: Gem::Requirement.new(">= 0")
      )
      obj = test_class.new(remote_spec: remote_spec)
      expect(obj.matches_current_metadata?).to be true
      expect(obj.matches_current_ruby?).to be true
    end

    it "returns false when remote Ruby version requirement is not satisfied" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 99.0.0"),
        required_rubygems_version: Gem::Requirement.new(">= 0")
      )
      obj = test_class.new(remote_spec: remote_spec)
      expect(obj.matches_current_metadata?).to be false
      expect(obj.matches_current_ruby?).to be false
    end

    it "returns false when remote RubyGems version requirement is not satisfied" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 0"),
        required_rubygems_version: Gem::Requirement.new(">= 99.0.0")
      )
      obj = test_class.new(remote_spec: remote_spec)
      expect(obj.matches_current_metadata?).to be false
      expect(obj.matches_current_rubygems?).to be false
    end
  end

  describe "version filtering" do
    it "correctly applies version requirements from the remote spec" do
      current_ruby = Gem.ruby_version
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new("~> #{current_ruby.segments[0]}.0"),
        required_rubygems_version: Gem::Requirement.new(">= 0")
      )
      obj = test_class.new(remote_spec: remote_spec)
      expect(obj.matches_current_ruby?).to be true
      expect(obj.matches_current_metadata?).to be true
    end

    it "rejects a spec when the ruby version requirement is strictly below current" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new("< 1.0"),
        required_rubygems_version: Gem::Requirement.new(">= 0")
      )
      obj = test_class.new(remote_spec: remote_spec)
      expect(obj.matches_current_ruby?).to be false
      expect(obj.matches_current_metadata?).to be false
    end
  end

  describe "inherited MatchMetadata methods" do
    it "exposes expanded_dependencies through the module chain" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.new(">= 2.0"),
        required_rubygems_version: Gem::Requirement.new(">= 1.0")
      )
      obj = test_class.new(remote_spec: remote_spec)
      # Trigger lazy initialization of @required_ruby_version and @required_rubygems_version
      obj.matches_current_metadata?
      result = obj.expanded_dependencies
      expect(result).to be_a(Array)
      names = result.map(&:name)
      expect(names).to include("Ruby\0")
    end

    it "exposes metadata_dependency through the module chain" do
      remote_spec = double("remote_spec",
        required_ruby_version: Gem::Requirement.default,
        required_rubygems_version: Gem::Requirement.default
      )
      obj = test_class.new(remote_spec: remote_spec)
      dep = obj.metadata_dependency("Ruby", Gem::Requirement.new(">= 2.0"))
      expect(dep).to be_a(Gem::Dependency)
      expect(dep.name).to eq("Ruby\0")
    end
  end
end
