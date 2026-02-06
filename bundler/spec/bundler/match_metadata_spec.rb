# frozen_string_literal: true

require "spec_helper"
require "bundler/match_metadata"

RSpec.describe Bundler::MatchMetadata do
  # Lightweight test class that includes the production MatchMetadata module.
  # Provides the @required_ruby_version, @required_rubygems_version instance
  # variables and the runtime_dependencies method the module expects its
  # host object to define. No business logic is reimplemented here — this
  # class is pure test-setup scaffolding for invoking real production methods.
  let(:test_class) do
    mod = described_class
    Class.new do
      include mod

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

  subject { test_class.new }

  describe "#matches_current_metadata?" do
    context "when both Ruby and RubyGems versions satisfy requirements" do
      it "returns true" do
        obj = test_class.new(
          ruby_version: Gem::Requirement.new(">= 0"),
          rubygems_version: Gem::Requirement.new(">= 0")
        )
        result = obj.matches_current_metadata?
        expect(result).to be_truthy
        expect(result).to eq(obj.matches_current_ruby? && obj.matches_current_rubygems?)
      end
    end

    context "when Ruby version does not match" do
      it "returns false" do
        obj = test_class.new(
          ruby_version: Gem::Requirement.new(">= 99.0.0"),
          rubygems_version: Gem::Requirement.new(">= 0")
        )
        expect(obj.matches_current_metadata?).to be_falsey
        expect(obj.matches_current_ruby?).to be false
      end
    end

    context "when RubyGems version does not match" do
      it "returns false" do
        obj = test_class.new(
          ruby_version: Gem::Requirement.new(">= 0"),
          rubygems_version: Gem::Requirement.new(">= 99.0.0")
        )
        expect(obj.matches_current_metadata?).to be_falsey
        expect(obj.matches_current_rubygems?).to be false
      end
    end

    context "when neither Ruby nor RubyGems version matches" do
      it "returns false" do
        obj = test_class.new(
          ruby_version: Gem::Requirement.new(">= 99.0.0"),
          rubygems_version: Gem::Requirement.new(">= 99.0.0")
        )
        expect(obj.matches_current_metadata?).to be false
        expect(obj.matches_current_ruby?).to be false
      end
    end
  end

  describe "#matches_current_ruby?" do
    context "when Gem.ruby_version satisfies the required_ruby_version" do
      it "returns true" do
        obj = test_class.new(ruby_version: Gem::Requirement.new(">= 0"))
        expect(obj.matches_current_ruby?).to be_truthy
        expect(Gem.ruby_version).to be_a(Gem::Version)
      end
    end

    context "with the default requirement" do
      it "returns true for any version" do
        obj = test_class.new(ruby_version: Gem::Requirement.default)
        expect(obj.matches_current_ruby?).to be true
        expect(obj.matches_current_ruby?).to eq(true)
      end
    end

    context "with an incompatible Ruby version requirement" do
      it "returns false" do
        obj = test_class.new(ruby_version: Gem::Requirement.new("= 1.0.0"))
        expect(obj.matches_current_ruby?).to be_falsey
        expect(obj.matches_current_metadata?).to be false
      end
    end

    context "when the current Ruby version is within a broad major version constraint" do
      it "returns true" do
        current = Gem.ruby_version
        major = current.segments[0]
        obj = test_class.new(ruby_version: Gem::Requirement.new(">= #{major}.0"))
        expect(obj.matches_current_ruby?).to be true
        expect(obj.matches_current_metadata?).to be_truthy
      end
    end
  end

  describe "#matches_current_rubygems?" do
    context "when Gem.rubygems_version satisfies the required_rubygems_version" do
      it "returns true" do
        obj = test_class.new(rubygems_version: Gem::Requirement.new(">= 0"))
        expect(obj.matches_current_rubygems?).to be_truthy
        expect(Gem.rubygems_version).to be_a(Gem::Version)
      end
    end

    context "with the default requirement" do
      it "returns true for any version" do
        obj = test_class.new(rubygems_version: Gem::Requirement.default)
        expect(obj.matches_current_rubygems?).to be true
        expect(obj.matches_current_rubygems?).to eq(true)
      end
    end

    context "with an incompatible RubyGems version requirement" do
      it "returns false" do
        obj = test_class.new(rubygems_version: Gem::Requirement.new("= 0.0.1"))
        expect(obj.matches_current_rubygems?).to be_falsey
        expect(obj.matches_current_metadata?).to be false
      end
    end
  end

  describe "#expanded_dependencies" do
    context "with non-default Ruby and RubyGems requirements" do
      before do
        @obj = test_class.new(
          ruby_version: Gem::Requirement.new(">= 2.0"),
          rubygems_version: Gem::Requirement.new(">= 1.0")
        )
      end

      it "returns metadata dependencies for both Ruby and RubyGems" do
        result = @obj.expanded_dependencies
        expect(result).to be_a(Array)
        expect(result.length).to eq(2)
      end

      it "includes entries with null-byte-suffixed names" do
        names = @obj.expanded_dependencies.map(&:name)
        expect(names).to include("Ruby\0")
        expect(names).to include("RubyGems\0")
      end
    end

    context "when runtime_dependencies are provided" do
      it "prepends them before metadata dependencies" do
        dep = Gem::Dependency.new("somegem", ">= 1.0")
        obj = test_class.new(
          ruby_version: Gem::Requirement.new(">= 2.0"),
          rubygems_version: Gem::Requirement.new(">= 1.0"),
          deps: [dep]
        )
        result = obj.expanded_dependencies
        expect(result.length).to eq(3)
        expect(result.first.name).to eq("somegem")
      end
    end

    context "when requirements are default (none)" do
      it "compacts away nil metadata dependencies" do
        obj = test_class.new(
          ruby_version: Gem::Requirement.default,
          rubygems_version: Gem::Requirement.default
        )
        result = obj.expanded_dependencies
        expect(result).to be_a(Array)
        expect(result.none?(&:nil?)).to be true
      end
    end

    context "when only one requirement is non-default" do
      it "includes only the non-default metadata dependency" do
        obj = test_class.new(
          ruby_version: Gem::Requirement.new(">= 2.0"),
          rubygems_version: Gem::Requirement.default
        )
        result = obj.expanded_dependencies
        expect(result.length).to eq(1)
        expect(result.first.name).to eq("Ruby\0")
      end
    end
  end

  describe "#metadata_dependency" do
    context "with a valid non-default requirement" do
      it "creates a Gem::Dependency with a null-byte-suffixed name" do
        dep = subject.metadata_dependency("Ruby", Gem::Requirement.new(">= 2.0"))
        expect(dep).to be_a(Gem::Dependency)
        expect(dep.name).to eq("Ruby\0")
      end
    end

    context "when the requirement object is forwarded" do
      it "sets the matching requirement on the Gem::Dependency" do
        req = Gem::Requirement.new(">= 3.0")
        dep = subject.metadata_dependency("RubyGems", req)
        expect(dep).to be_a(Gem::Dependency)
        expect(dep.requirement).to eq(req)
      end
    end

    context "when the requirement is nil" do
      it "returns nil" do
        result = subject.metadata_dependency("Ruby", nil)
        expect(result).to be_nil
        expect(result).to eq(nil)
      end
    end

    context "when the requirement is the default (none? is true)" do
      it "returns nil for default requirements" do
        result = subject.metadata_dependency("Ruby", Gem::Requirement.default)
        expect(result).to be_nil
        expect(subject.metadata_dependency("RubyGems", Gem::Requirement.default)).to be_nil
      end
    end

    context "with a pessimistic version constraint" do
      it "returns a Gem::Dependency with the correct null-byte name" do
        req = Gem::Requirement.new("~> 2.5")
        dep = subject.metadata_dependency("TestName", req)
        expect(dep).to be_a(Gem::Dependency)
        expect(dep.name).to eq("TestName\0")
      end
    end
  end
end
