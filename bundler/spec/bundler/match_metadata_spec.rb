# frozen_string_literal: true

require "spec_helper"
require "bundler/match_metadata"

RSpec.describe Bundler::MatchMetadata do
  # Test class that includes MatchMetadata and provides the required instance
  # variables and runtime_dependencies method for testing the module's behavior.
  let(:test_class) do
    Class.new do
      include Bundler::MatchMetadata

      attr_accessor :required_ruby_version, :required_rubygems_version

      def initialize(ruby_version: Gem::Requirement.default, rubygems_version: Gem::Requirement.default, deps: [])
        @required_ruby_version = ruby_version
        @required_rubygems_version = rubygems_version
        @deps = deps
      end

      def runtime_dependencies
        @deps
      end
    end
  end

  describe "#matches_current_metadata?" do
    it "returns true when both Ruby and RubyGems versions satisfy requirements" do
      obj = test_class.new(
        ruby_version: Gem::Requirement.new(">= 0"),
        rubygems_version: Gem::Requirement.new(">= 0")
      )
      result = obj.matches_current_metadata?
      expect(result).to be true
      expect(result).to eq(obj.matches_current_ruby? && obj.matches_current_rubygems?)
    end

    it "returns false when Ruby version does not match" do
      obj = test_class.new(
        ruby_version: Gem::Requirement.new(">= 99.0.0"),
        rubygems_version: Gem::Requirement.new(">= 0")
      )
      expect(obj.matches_current_metadata?).to be false
      expect(obj.matches_current_ruby?).to be false
    end

    it "returns false when RubyGems version does not match" do
      obj = test_class.new(
        ruby_version: Gem::Requirement.new(">= 0"),
        rubygems_version: Gem::Requirement.new(">= 99.0.0")
      )
      expect(obj.matches_current_metadata?).to be false
      expect(obj.matches_current_rubygems?).to be false
    end

    it "returns false when neither Ruby nor RubyGems version matches" do
      obj = test_class.new(
        ruby_version: Gem::Requirement.new(">= 99.0.0"),
        rubygems_version: Gem::Requirement.new(">= 99.0.0")
      )
      expect(obj.matches_current_metadata?).to be false
      expect(obj.matches_current_ruby?).to be false
    end
  end

  describe "#matches_current_ruby?" do
    it "returns true when Gem.ruby_version satisfies the required_ruby_version" do
      obj = test_class.new(ruby_version: Gem::Requirement.new(">= 0"))
      expect(obj.matches_current_ruby?).to be true
      expect(Gem.ruby_version).to be_a(Gem::Version)
    end

    it "returns true with the default requirement (any version)" do
      obj = test_class.new(ruby_version: Gem::Requirement.default)
      expect(obj.matches_current_ruby?).to be true
      expect(obj.matches_current_ruby?).to eq(true)
    end

    it "returns false for an incompatible Ruby version requirement" do
      obj = test_class.new(ruby_version: Gem::Requirement.new("= 1.0.0"))
      expect(obj.matches_current_ruby?).to be false
      expect(obj.matches_current_metadata?).to be false
    end

    it "returns true when the current Ruby version is within a pessimistic constraint" do
      current = Gem.ruby_version
      major = current.segments[0]
      obj = test_class.new(ruby_version: Gem::Requirement.new(">= #{major}.0"))
      expect(obj.matches_current_ruby?).to be true
      expect(obj.matches_current_metadata?).to be true
    end
  end

  describe "#matches_current_rubygems?" do
    it "returns true when Gem.rubygems_version satisfies the required_rubygems_version" do
      obj = test_class.new(rubygems_version: Gem::Requirement.new(">= 0"))
      expect(obj.matches_current_rubygems?).to be true
      expect(Gem.rubygems_version).to be_a(Gem::Version)
    end

    it "returns true with the default requirement (any version)" do
      obj = test_class.new(rubygems_version: Gem::Requirement.default)
      expect(obj.matches_current_rubygems?).to be true
      expect(obj.matches_current_rubygems?).to eq(true)
    end

    it "returns false for an incompatible RubyGems version requirement" do
      obj = test_class.new(rubygems_version: Gem::Requirement.new("= 0.0.1"))
      expect(obj.matches_current_rubygems?).to be false
      expect(obj.matches_current_metadata?).to be false
    end
  end

  describe "#expanded_dependencies" do
    it "returns runtime_dependencies plus metadata dependencies for Ruby and RubyGems" do
      ruby_req = Gem::Requirement.new(">= 2.0")
      rubygems_req = Gem::Requirement.new(">= 1.0")
      obj = test_class.new(ruby_version: ruby_req, rubygems_version: rubygems_req)
      result = obj.expanded_dependencies
      expect(result).to be_a(Array)
      expect(result.length).to eq(2)
    end

    it "includes metadata dependencies with null-byte-suffixed names" do
      ruby_req = Gem::Requirement.new(">= 2.0")
      rubygems_req = Gem::Requirement.new(">= 1.0")
      obj = test_class.new(ruby_version: ruby_req, rubygems_version: rubygems_req)
      result = obj.expanded_dependencies
      names = result.map(&:name)
      expect(names).to include("Ruby\0")
      expect(names).to include("RubyGems\0")
    end

    it "prepends runtime_dependencies before metadata dependencies" do
      dep = Gem::Dependency.new("somegem", ">= 1.0")
      ruby_req = Gem::Requirement.new(">= 2.0")
      rubygems_req = Gem::Requirement.new(">= 1.0")
      obj = test_class.new(ruby_version: ruby_req, rubygems_version: rubygems_req, deps: [dep])
      result = obj.expanded_dependencies
      expect(result.length).to eq(3)
      expect(result.first.name).to eq("somegem")
    end

    it "skips nil requirements via compact" do
      obj = test_class.new(
        ruby_version: Gem::Requirement.default,
        rubygems_version: Gem::Requirement.default
      )
      result = obj.expanded_dependencies
      # Default requirements satisfy none? => true, so metadata_dependency returns nil
      # compact removes nils
      expect(result).to be_a(Array)
      expect(result.none? { |d| d.nil? }).to be true
    end
  end

  describe "#metadata_dependency" do
    let(:obj) { test_class.new }

    it "creates a Gem::Dependency with a null-byte-suffixed name" do
      dep = obj.metadata_dependency("Ruby", Gem::Requirement.new(">= 2.0"))
      expect(dep).to be_a(Gem::Dependency)
      expect(dep.name).to eq("Ruby\0")
    end

    it "passes the requirement through to the Gem::Dependency" do
      req = Gem::Requirement.new(">= 3.0")
      dep = obj.metadata_dependency("RubyGems", req)
      expect(dep).to be_a(Gem::Dependency)
      expect(dep.requirement).to eq(req)
    end

    it "returns nil for nil requirement" do
      result = obj.metadata_dependency("Ruby", nil)
      expect(result).to be_nil
      expect(result).to eq(nil)
    end

    it "returns nil for a requirement where none? is true (default)" do
      result = obj.metadata_dependency("Ruby", Gem::Requirement.default)
      expect(result).to be_nil
      expect(obj.metadata_dependency("RubyGems", Gem::Requirement.default)).to be_nil
    end

    it "returns a Gem::Dependency for a non-default, non-nil requirement" do
      req = Gem::Requirement.new("~> 2.5")
      dep = obj.metadata_dependency("TestName", req)
      expect(dep).to be_a(Gem::Dependency)
      expect(dep.name).to eq("TestName\0")
    end
  end
end
