# frozen_string_literal: true

require "spec_helper"
require "bundler/source_map"

RSpec.describe Bundler::SourceMap do
  # Helper to build a lightweight mock source that responds to the interface
  # methods consumed by SourceMap (add_dependency_names, spec_names, unmet_deps, etc.)
  def build_mock_source(name, spec_names: [], unmet_deps: [])
    source = double("source:#{name}", to_s: name)
    allow(source).to receive(:add_dependency_names)
    allow(source).to receive(:spec_names).and_return(spec_names)
    allow(source).to receive(:unmet_deps).and_return(unmet_deps)
    source
  end

  # Helper to build a mock dependency object with name and optional source
  def build_mock_dep(name, source: nil)
    dep = double("dep:#{name}", name: name, source: source)
    dep
  end

  # Helper to build a mock locked spec with name and source
  def build_mock_locked_spec(name, source)
    double("locked:#{name}", name: name, source: source)
  end

  # Helper to build a mock sources list (SourceList-like object)
  def build_mock_sources(default:, non_default: [])
    sources = double("sources")
    allow(sources).to receive(:default_source).and_return(default)
    allow(sources).to receive(:non_default_explicit_sources).and_return(non_default)
    sources
  end

  describe "#initialize" do
    it "stores sources, dependencies, and locked_specs as accessible attributes" do
      default_source = build_mock_source("default")
      sources = build_mock_sources(default: default_source)
      deps = [build_mock_dep("rails")]
      locked = [build_mock_locked_spec("rails", default_source)]

      source_map = described_class.new(sources, deps, locked)

      expect(source_map.sources).to eq(sources)
      expect(source_map.dependencies).to eq(deps)
      expect(source_map.locked_specs).to eq(locked)
    end

    it "accepts empty collections for all arguments" do
      default_source = build_mock_source("default")
      sources = build_mock_sources(default: default_source)

      source_map = described_class.new(sources, [], [])

      expect(source_map.sources).to eq(sources)
      expect(source_map.dependencies).to eq([])
      expect(source_map.locked_specs).to eq([])
    end
  end

  describe "#direct_requirements" do
    context "when all dependencies use the default source" do
      it "maps each dependency name to the default source" do
        default_source = build_mock_source("rubygems")
        sources = build_mock_sources(default: default_source)
        deps = [
          build_mock_dep("rails"),
          build_mock_dep("nokogiri"),
        ]

        source_map = described_class.new(sources, deps, [])
        result = source_map.direct_requirements

        expect(result).to be_a(Hash)
        expect(result["rails"]).to eq(default_source)
        expect(result["nokogiri"]).to eq(default_source)
      end

      it "calls add_dependency_names on the default source for each dependency" do
        default_source = build_mock_source("rubygems")
        sources = build_mock_sources(default: default_source)
        deps = [build_mock_dep("rails")]

        source_map = described_class.new(sources, deps, [])
        source_map.direct_requirements

        expect(default_source).to have_received(:add_dependency_names).with("rails")
      end
    end

    context "when a dependency has an explicit source" do
      it "maps the dependency to its explicit source instead of the default" do
        default_source = build_mock_source("rubygems")
        custom_source = build_mock_source("custom_git")
        sources = build_mock_sources(default: default_source)
        deps = [
          build_mock_dep("rails", source: custom_source),
          build_mock_dep("nokogiri"),
        ]

        source_map = described_class.new(sources, deps, [])
        result = source_map.direct_requirements

        expect(result["rails"]).to eq(custom_source)
        expect(result["nokogiri"]).to eq(default_source)
      end

      it "calls add_dependency_names on the explicit source for that dependency" do
        default_source = build_mock_source("rubygems")
        custom_source = build_mock_source("custom_git")
        sources = build_mock_sources(default: default_source)
        deps = [build_mock_dep("rails", source: custom_source)]

        source_map = described_class.new(sources, deps, [])
        source_map.direct_requirements

        expect(custom_source).to have_received(:add_dependency_names).with("rails")
      end
    end

    context "with no dependencies" do
      it "returns an empty hash" do
        default_source = build_mock_source("rubygems")
        sources = build_mock_sources(default: default_source)

        source_map = described_class.new(sources, [], [])
        result = source_map.direct_requirements

        expect(result).to eq({})
      end
    end

    context "with multiple dependencies" do
      it "creates a mapping entry for each dependency" do
        default_source = build_mock_source("rubygems")
        sources = build_mock_sources(default: default_source)
        deps = [
          build_mock_dep("rails"),
          build_mock_dep("sinatra"),
          build_mock_dep("puma"),
        ]

        source_map = described_class.new(sources, deps, [])
        result = source_map.direct_requirements

        expect(result.keys).to contain_exactly("rails", "sinatra", "puma")
      end
    end

    it "memoizes the result across multiple calls" do
      default_source = build_mock_source("rubygems")
      sources = build_mock_sources(default: default_source)
      deps = [build_mock_dep("rails")]

      source_map = described_class.new(sources, deps, [])

      first_call = source_map.direct_requirements
      second_call = source_map.direct_requirements

      expect(first_call).to equal(second_call)
    end
  end

  describe "#pinned_spec_names" do
    context "with no skip argument" do
      it "returns all dependency names from direct_requirements" do
        default_source = build_mock_source("rubygems")
        sources = build_mock_sources(default: default_source)
        deps = [
          build_mock_dep("rails"),
          build_mock_dep("nokogiri"),
        ]

        source_map = described_class.new(sources, deps, [])
        result = source_map.pinned_spec_names

        expect(result).to contain_exactly("rails", "nokogiri")
      end
    end

    context "when skip matches a specific source" do
      it "excludes dependencies assigned to the skipped source" do
        default_source = build_mock_source("rubygems")
        custom_source = build_mock_source("custom_git")
        sources = build_mock_sources(default: default_source)
        deps = [
          build_mock_dep("rails", source: custom_source),
          build_mock_dep("nokogiri"),
        ]

        source_map = described_class.new(sources, deps, [])
        result = source_map.pinned_spec_names(custom_source)

        expect(result).to contain_exactly("nokogiri")
        expect(result).not_to include("rails")
      end
    end

    context "when skip does not match any source" do
      it "returns all dependency names" do
        default_source = build_mock_source("rubygems")
        unrelated_source = build_mock_source("unrelated")
        sources = build_mock_sources(default: default_source)
        deps = [
          build_mock_dep("rails"),
          build_mock_dep("nokogiri"),
        ]

        source_map = described_class.new(sources, deps, [])
        result = source_map.pinned_spec_names(unrelated_source)

        expect(result).to contain_exactly("rails", "nokogiri")
      end
    end

    context "when skip matches the default source" do
      it "excludes all dependencies using the default source" do
        default_source = build_mock_source("rubygems")
        custom_source = build_mock_source("custom_git")
        sources = build_mock_sources(default: default_source)
        deps = [
          build_mock_dep("rails", source: custom_source),
          build_mock_dep("nokogiri"),
        ]

        source_map = described_class.new(sources, deps, [])
        result = source_map.pinned_spec_names(default_source)

        expect(result).to contain_exactly("rails")
        expect(result).not_to include("nokogiri")
      end
    end

    context "with no dependencies" do
      it "returns an empty array" do
        default_source = build_mock_source("rubygems")
        sources = build_mock_sources(default: default_source)

        source_map = described_class.new(sources, [], [])
        result = source_map.pinned_spec_names

        expect(result).to be_empty
      end
    end
  end

  describe "#locked_requirements" do
    context "with locked specs" do
      it "maps each locked spec name to its source" do
        source_a = build_mock_source("source_a")
        source_b = build_mock_source("source_b")
        default_source = build_mock_source("rubygems")
        sources = build_mock_sources(default: default_source)
        locked = [
          build_mock_locked_spec("rails", source_a),
          build_mock_locked_spec("pg", source_b),
        ]

        source_map = described_class.new(sources, [], locked)
        result = source_map.locked_requirements

        expect(result).to be_a(Hash)
        expect(result["rails"]).to eq(source_a)
        expect(result["pg"]).to eq(source_b)
      end

      it "calls add_dependency_names on each locked spec's source" do
        source_a = build_mock_source("source_a")
        default_source = build_mock_source("rubygems")
        sources = build_mock_sources(default: default_source)
        locked = [build_mock_locked_spec("rails", source_a)]

        source_map = described_class.new(sources, [], locked)
        source_map.locked_requirements

        expect(source_a).to have_received(:add_dependency_names).with("rails")
      end
    end

    context "with no locked specs" do
      it "returns an empty hash" do
        default_source = build_mock_source("rubygems")
        sources = build_mock_sources(default: default_source)

        source_map = described_class.new(sources, [], [])
        result = source_map.locked_requirements

        expect(result).to eq({})
      end
    end

    context "with multiple locked specs from the same source" do
      it "maps each spec name to the same source" do
        shared_source = build_mock_source("shared")
        default_source = build_mock_source("rubygems")
        sources = build_mock_sources(default: default_source)
        locked = [
          build_mock_locked_spec("rails", shared_source),
          build_mock_locked_spec("actionpack", shared_source),
        ]

        source_map = described_class.new(sources, [], locked)
        result = source_map.locked_requirements

        expect(result["rails"]).to eq(shared_source)
        expect(result["actionpack"]).to eq(shared_source)
      end
    end

    it "memoizes the result across multiple calls" do
      default_source = build_mock_source("rubygems")
      sources = build_mock_sources(default: default_source)
      locked = [build_mock_locked_spec("rails", default_source)]

      source_map = described_class.new(sources, [], locked)

      first_call = source_map.locked_requirements
      second_call = source_map.locked_requirements

      expect(first_call).to equal(second_call)
    end
  end

  describe "#all_requirements" do
    context "when there are no non-default explicit sources" do
      it "returns only the direct requirements" do
        default_source = build_mock_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        sources = build_mock_sources(default: default_source, non_default: [])
        deps = [build_mock_dep("rails")]

        source_map = described_class.new(sources, deps, [])
        result = source_map.all_requirements

        expect(result["rails"]).to eq(default_source)
      end
    end

    context "when a non-default source provides an unresolved indirect dependency" do
      it "adds the indirect dependency mapped to the non-default source" do
        default_source = build_mock_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        custom_source = build_mock_source("custom",
          spec_names: ["indirect_gem"],
          unmet_deps: [])
        sources = build_mock_sources(default: default_source, non_default: [custom_source])
        deps = [build_mock_dep("rails")]

        source_map = described_class.new(sources, deps, [])
        result = source_map.all_requirements

        expect(result["indirect_gem"]).to eq(custom_source)
        expect(result["rails"]).to eq(default_source)
      end
    end

    context "when an indirect dependency is already pinned" do
      it "does not reassign the dependency to the non-default source" do
        default_source = build_mock_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        custom_source = build_mock_source("custom",
          spec_names: ["rails"],
          unmet_deps: [])
        sources = build_mock_sources(default: default_source, non_default: [custom_source])
        deps = [build_mock_dep("rails")]

        source_map = described_class.new(sources, deps, [])
        result = source_map.all_requirements

        # rails is already pinned to default_source via direct_requirements,
        # so it should remain unchanged
        expect(result["rails"]).to eq(default_source)
      end
    end

    context "when an indirect dependency appears in two non-default sources" do
      it "raises a SecurityError with a descriptive message" do
        default_source = build_mock_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)

        source_a = build_mock_source("source_a",
          spec_names: ["shared_gem"],
          unmet_deps: [])
        source_b = build_mock_source("source_b",
          spec_names: ["shared_gem"],
          unmet_deps: [])

        sources = build_mock_sources(default: default_source, non_default: [source_a, source_b])

        source_map = described_class.new(sources, [], [])

        expect { source_map.all_requirements }.to raise_error(Bundler::SecurityError, /shared_gem/)
      end

      it "includes both source names in the error message" do
        default_source = build_mock_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)

        source_a = build_mock_source("source_a",
          spec_names: ["shared_gem"],
          unmet_deps: [])
        source_b = build_mock_source("source_b",
          spec_names: ["shared_gem"],
          unmet_deps: [])

        sources = build_mock_sources(default: default_source, non_default: [source_a, source_b])

        source_map = described_class.new(sources, [], [])

        expect { source_map.all_requirements }.to raise_error(Bundler::SecurityError, /found in multiple relevant sources/)
      end
    end

    context "when non-default sources have unmet dependencies" do
      it "adds unmet dependency names to the default source" do
        default_source = build_mock_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        custom_source = build_mock_source("custom",
          spec_names: [],
          unmet_deps: ["unmet_dep_a", "unmet_dep_b"])
        sources = build_mock_sources(default: default_source, non_default: [custom_source])

        source_map = described_class.new(sources, [], [])
        source_map.all_requirements

        # The production code calls:
        # sources.default_source.add_dependency_names(unmet_deps.flatten - requirements.keys)
        expect(default_source).to have_received(:add_dependency_names).with(
          ["unmet_dep_a", "unmet_dep_b"]
        )
      end
    end

    context "when unmet deps overlap with existing requirements" do
      it "does not add duplicate dependency names to the default source" do
        default_source = build_mock_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        custom_source = build_mock_source("custom",
          spec_names: [],
          unmet_deps: ["rails"])
        sources = build_mock_sources(default: default_source, non_default: [custom_source])
        deps = [build_mock_dep("rails")]

        source_map = described_class.new(sources, deps, [])
        source_map.all_requirements

        # The unmet dep "rails" is already in requirements, so it should be excluded
        expect(default_source).to have_received(:add_dependency_names).with([])
      end
    end

    context "with empty sources and dependencies" do
      it "returns an empty hash and adds no unmet deps" do
        default_source = build_mock_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        sources = build_mock_sources(default: default_source, non_default: [])

        source_map = described_class.new(sources, [], [])
        result = source_map.all_requirements

        expect(result).to eq({})
        expect(default_source).to have_received(:add_dependency_names).with([])
      end
    end
  end

  describe "integration scenarios" do
    context "a typical Gemfile scenario with default and git sources" do
      it "correctly maps direct dependencies to their sources" do
        default_source = build_mock_source("rubygems.org")
        allow(default_source).to receive(:add_dependency_names)
        git_source = build_mock_source("git://github.com/rails/rails.git",
          spec_names: [],
          unmet_deps: [])
        sources = build_mock_sources(default: default_source, non_default: [git_source])

        deps = [
          build_mock_dep("rails", source: git_source),
          build_mock_dep("pg"),
          build_mock_dep("puma"),
        ]

        locked = [
          build_mock_locked_spec("rails", git_source),
          build_mock_locked_spec("pg", default_source),
          build_mock_locked_spec("puma", default_source),
        ]

        source_map = described_class.new(sources, deps, locked)

        direct = source_map.direct_requirements
        expect(direct["rails"]).to eq(git_source)
        expect(direct["pg"]).to eq(default_source)
        expect(direct["puma"]).to eq(default_source)

        locked_reqs = source_map.locked_requirements
        expect(locked_reqs["rails"]).to eq(git_source)
        expect(locked_reqs["pg"]).to eq(default_source)

        pinned = source_map.pinned_spec_names
        expect(pinned).to contain_exactly("rails", "pg", "puma")

        pinned_without_git = source_map.pinned_spec_names(git_source)
        expect(pinned_without_git).to contain_exactly("pg", "puma")
      end
    end

    context "all dependencies share the same source" do
      it "maps everything to the default source" do
        default_source = build_mock_source("rubygems.org")
        allow(default_source).to receive(:add_dependency_names)
        sources = build_mock_sources(default: default_source, non_default: [])

        deps = [
          build_mock_dep("rails"),
          build_mock_dep("pg"),
        ]

        source_map = described_class.new(sources, deps, [])

        result = source_map.all_requirements
        expect(result["rails"]).to eq(default_source)
        expect(result["pg"]).to eq(default_source)
      end
    end

    context "a single dependency with a custom source" do
      it "isolates the pinned dependency from the default source" do
        default_source = build_mock_source("rubygems.org")
        allow(default_source).to receive(:add_dependency_names)
        private_source = build_mock_source("private-gems.example.com",
          spec_names: [],
          unmet_deps: [])
        sources = build_mock_sources(default: default_source, non_default: [private_source])

        deps = [
          build_mock_dep("my_private_gem", source: private_source),
          build_mock_dep("rails"),
        ]

        source_map = described_class.new(sources, deps, [])

        direct = source_map.direct_requirements
        expect(direct["my_private_gem"]).to eq(private_source)
        expect(direct["rails"]).to eq(default_source)

        pinned = source_map.pinned_spec_names(private_source)
        expect(pinned).to contain_exactly("rails")
      end
    end
  end
end
