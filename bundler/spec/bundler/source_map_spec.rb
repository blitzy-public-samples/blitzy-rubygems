# frozen_string_literal: true

require "spec_helper"
require "bundler/source_map"

RSpec.describe Bundler::SourceMap do
  # Lightweight mock source responding to the SourceMap-consumed interface:
  # add_dependency_names, spec_names, unmet_deps, to_s
  def build_source(name, spec_names: [], unmet_deps: [])
    source = double("source:#{name}", to_s: name)
    allow(source).to receive(:add_dependency_names)
    allow(source).to receive(:spec_names).and_return(spec_names)
    allow(source).to receive(:unmet_deps).and_return(unmet_deps)
    source
  end

  # Mock dependency with name and optional explicit source
  def build_dep(name, source: nil)
    double("dep:#{name}", name: name, source: source)
  end

  # Mock locked spec with name and source
  def build_locked_spec(name, source)
    double("locked:#{name}", name: name, source: source)
  end

  # Mock SourceList-like object with default_source and non_default_explicit_sources
  def build_sources(default:, non_default: [])
    sources = double("sources")
    allow(sources).to receive(:default_source).and_return(default)
    allow(sources).to receive(:non_default_explicit_sources).and_return(non_default)
    sources
  end

  describe "#initialize" do
    let(:default_source) { build_source("default") }
    let(:sources) { build_sources(default: default_source) }
    let(:deps) { [build_dep("rails")] }
    let(:locked) { [build_locked_spec("rails", default_source)] }

    subject { described_class.new(sources, deps, locked) }

    it "stores sources, dependencies, and locked_specs as accessible attributes" do
      expect(subject.sources).to eq(sources)
      expect(subject.dependencies).to eq(deps)
      expect(subject.locked_specs).to eq(locked)
    end

    it "responds to attr_reader accessors for all stored collections" do
      expect(subject).to respond_to(:sources)
      expect(subject).to respond_to(:dependencies)
      expect(subject).to respond_to(:locked_specs)
    end

    it "accepts empty collections for dependencies and locked_specs" do
      source_map = described_class.new(sources, [], [])

      expect(source_map.dependencies).to be_a(Array)
      expect(source_map.dependencies).to eq([])
      expect(source_map.locked_specs).to eq([])
    end
  end

  describe "#direct_requirements" do
    context "when all dependencies use the default source" do
      let(:default_source) { build_source("rubygems") }
      let(:sources) { build_sources(default: default_source) }

      it "maps each dependency name to the default source" do
        deps = [build_dep("rails"), build_dep("nokogiri")]
        source_map = described_class.new(sources, deps, [])

        result = source_map.direct_requirements

        expect(result).to be_a(Hash)
        expect(result["rails"]).to eq(default_source)
        expect(result["nokogiri"]).to eq(default_source)
      end

      it "calls add_dependency_names on the default source for each dependency" do
        deps = [build_dep("rails"), build_dep("nokogiri")]
        source_map = described_class.new(sources, deps, [])

        source_map.direct_requirements

        expect(default_source).to have_received(:add_dependency_names).with("rails")
        expect(default_source).to have_received(:add_dependency_names).with("nokogiri")
      end
    end

    context "when a dependency has an explicit source" do
      let(:default_source) { build_source("rubygems") }
      let(:custom_source) { build_source("custom_git") }
      let(:sources) { build_sources(default: default_source) }

      it "maps the dependency to its explicit source instead of the default" do
        deps = [
          build_dep("rails", source: custom_source),
          build_dep("nokogiri"),
        ]
        source_map = described_class.new(sources, deps, [])

        result = source_map.direct_requirements

        expect(result["rails"]).to eq(custom_source)
        expect(result["nokogiri"]).to eq(default_source)
      end

      it "calls add_dependency_names on the explicit source for that dependency" do
        deps = [build_dep("rails", source: custom_source)]
        source_map = described_class.new(sources, deps, [])

        source_map.direct_requirements

        expect(custom_source).to have_received(:add_dependency_names).with("rails")
        expect(default_source).not_to have_received(:add_dependency_names).with("rails")
      end
    end

    context "with no dependencies" do
      it "returns an empty hash with no entries" do
        default_source = build_source("rubygems")
        sources = build_sources(default: default_source)
        source_map = described_class.new(sources, [], [])

        result = source_map.direct_requirements

        expect(result).to be_a(Hash)
        expect(result).to eq({})
      end
    end

    context "with multiple dependencies" do
      it "creates a mapping entry for every dependency provided" do
        default_source = build_source("rubygems")
        sources = build_sources(default: default_source)
        deps = [build_dep("rails"), build_dep("sinatra"), build_dep("puma")]
        source_map = described_class.new(sources, deps, [])

        result = source_map.direct_requirements

        expect(result.keys).to include("rails", "sinatra", "puma")
        expect(result.size).to eq(3)
      end
    end

    it "memoizes the result across multiple calls returning the same object" do
      default_source = build_source("rubygems")
      sources = build_sources(default: default_source)
      deps = [build_dep("rails")]
      source_map = described_class.new(sources, deps, [])

      first_call = source_map.direct_requirements
      second_call = source_map.direct_requirements

      expect(first_call).to be(second_call)
      expect(first_call).to equal(second_call)
    end
  end

  describe "#pinned_spec_names" do
    context "with no skip argument" do
      it "returns all dependency names from direct_requirements" do
        default_source = build_source("rubygems")
        sources = build_sources(default: default_source)
        deps = [build_dep("rails"), build_dep("nokogiri")]
        source_map = described_class.new(sources, deps, [])

        result = source_map.pinned_spec_names

        expect(result).to be_a(Array)
        expect(result).to include("rails", "nokogiri")
      end
    end

    context "when skip matches a specific source" do
      it "excludes dependencies assigned to the skipped source" do
        default_source = build_source("rubygems")
        custom_source = build_source("custom_git")
        sources = build_sources(default: default_source)
        deps = [
          build_dep("rails", source: custom_source),
          build_dep("nokogiri"),
        ]
        source_map = described_class.new(sources, deps, [])

        result = source_map.pinned_spec_names(custom_source)

        expect(result).to include("nokogiri")
        expect(result).not_to include("rails")
      end
    end

    context "when skip does not match any assigned source" do
      it "returns all dependency names unchanged" do
        default_source = build_source("rubygems")
        unrelated_source = build_source("unrelated")
        sources = build_sources(default: default_source)
        deps = [build_dep("rails"), build_dep("nokogiri")]
        source_map = described_class.new(sources, deps, [])

        result = source_map.pinned_spec_names(unrelated_source)

        expect(result).to include("rails", "nokogiri")
        expect(result.size).to eq(2)
      end
    end

    context "when skip matches the default source" do
      it "excludes all dependencies using the default source" do
        default_source = build_source("rubygems")
        custom_source = build_source("custom_git")
        sources = build_sources(default: default_source)
        deps = [
          build_dep("rails", source: custom_source),
          build_dep("nokogiri"),
        ]
        source_map = described_class.new(sources, deps, [])

        result = source_map.pinned_spec_names(default_source)

        expect(result).to include("rails")
        expect(result).not_to include("nokogiri")
      end
    end

    context "with no dependencies" do
      it "returns an empty array" do
        default_source = build_source("rubygems")
        sources = build_sources(default: default_source)
        source_map = described_class.new(sources, [], [])

        result = source_map.pinned_spec_names

        expect(result).to be_a(Array)
        expect(result).to be_empty
      end
    end
  end

  describe "#locked_requirements" do
    context "with locked specs from different sources" do
      let(:source_a) { build_source("source_a") }
      let(:source_b) { build_source("source_b") }
      let(:default_source) { build_source("rubygems") }
      let(:sources) { build_sources(default: default_source) }

      it "maps each locked spec name to its associated source" do
        locked = [
          build_locked_spec("rails", source_a),
          build_locked_spec("pg", source_b),
        ]
        source_map = described_class.new(sources, [], locked)

        result = source_map.locked_requirements

        expect(result).to be_a(Hash)
        expect(result["rails"]).to eq(source_a)
        expect(result["pg"]).to eq(source_b)
      end

      it "calls add_dependency_names on each locked spec source" do
        locked = [
          build_locked_spec("rails", source_a),
          build_locked_spec("pg", source_b),
        ]
        source_map = described_class.new(sources, [], locked)

        source_map.locked_requirements

        expect(source_a).to have_received(:add_dependency_names).with("rails")
        expect(source_b).to have_received(:add_dependency_names).with("pg")
      end
    end

    context "with no locked specs" do
      it "returns an empty hash with no entries" do
        default_source = build_source("rubygems")
        sources = build_sources(default: default_source)
        source_map = described_class.new(sources, [], [])

        result = source_map.locked_requirements

        expect(result).to be_a(Hash)
        expect(result).to eq({})
      end
    end

    context "with multiple locked specs from the same source" do
      it "maps each spec name to the shared source" do
        shared_source = build_source("shared")
        default_source = build_source("rubygems")
        sources = build_sources(default: default_source)
        locked = [
          build_locked_spec("rails", shared_source),
          build_locked_spec("actionpack", shared_source),
        ]
        source_map = described_class.new(sources, [], locked)

        result = source_map.locked_requirements

        expect(result["rails"]).to eq(shared_source)
        expect(result["actionpack"]).to eq(shared_source)
      end
    end

    it "memoizes the result across multiple calls returning the same object" do
      default_source = build_source("rubygems")
      sources = build_sources(default: default_source)
      locked = [build_locked_spec("rails", default_source)]
      source_map = described_class.new(sources, [], locked)

      first_call = source_map.locked_requirements
      second_call = source_map.locked_requirements

      expect(first_call).to be(second_call)
      expect(first_call).to equal(second_call)
    end
  end

  describe "#all_requirements" do
    context "when there are no non-default explicit sources" do
      it "returns only the direct requirements mapped to the default source" do
        default_source = build_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        sources = build_sources(default: default_source, non_default: [])
        deps = [build_dep("rails")]
        source_map = described_class.new(sources, deps, [])

        result = source_map.all_requirements

        expect(result["rails"]).to eq(default_source)
        expect(result.size).to eq(1)
      end
    end

    context "when a non-default source provides an unresolved indirect dependency" do
      it "adds the indirect dependency mapped to the non-default source" do
        default_source = build_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        custom_source = build_source("custom",
          spec_names: ["indirect_gem"],
          unmet_deps: [])
        sources = build_sources(default: default_source, non_default: [custom_source])
        deps = [build_dep("rails")]
        source_map = described_class.new(sources, deps, [])

        result = source_map.all_requirements

        expect(result).to include("indirect_gem" => custom_source)
        expect(result["rails"]).to eq(default_source)
      end
    end

    context "when an indirect dependency is already pinned via direct_requirements" do
      it "does not reassign the dependency to the non-default source" do
        default_source = build_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        custom_source = build_source("custom",
          spec_names: ["rails"],
          unmet_deps: [])
        sources = build_sources(default: default_source, non_default: [custom_source])
        deps = [build_dep("rails")]
        source_map = described_class.new(sources, deps, [])

        result = source_map.all_requirements

        expect(result["rails"]).to eq(default_source)
        expect(result.keys).to include("rails")
      end
    end

    context "when an indirect dependency appears in two non-default sources" do
      let(:default_source) do
        src = build_source("rubygems")
        allow(src).to receive(:add_dependency_names)
        src
      end
      let(:source_a) { build_source("source_a", spec_names: ["shared_gem"], unmet_deps: []) }
      let(:source_b) { build_source("source_b", spec_names: ["shared_gem"], unmet_deps: []) }
      let(:sources) { build_sources(default: default_source, non_default: [source_a, source_b]) }

      subject { described_class.new(sources, [], []) }

      it "raises a Bundler::SecurityError mentioning the conflicting gem name" do
        expect { subject.all_requirements }.to raise_error(Bundler::SecurityError) do |error|
          expect(error.message).to include("shared_gem")
        end
      end

      it "raises a Bundler::SecurityError with a message about multiple relevant sources" do
        expect { subject.all_requirements }.to raise_error(Bundler::SecurityError) do |error|
          expect(error.message).to include("found in multiple relevant sources")
        end
      end
    end

    context "when non-default sources have unmet dependencies" do
      it "adds unmet dependency names to the default source" do
        default_source = build_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        custom_source = build_source("custom",
          spec_names: [],
          unmet_deps: ["unmet_dep_a", "unmet_dep_b"])
        sources = build_sources(default: default_source, non_default: [custom_source])
        source_map = described_class.new(sources, [], [])

        source_map.all_requirements

        expect(default_source).to have_received(:add_dependency_names).with(
          ["unmet_dep_a", "unmet_dep_b"]
        )
        expect(default_source).to have_received(:add_dependency_names).at_least(:once)
      end
    end

    context "when unmet deps overlap with existing requirements" do
      it "excludes already-mapped dependency names from unmet deps passed to default source" do
        default_source = build_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        custom_source = build_source("custom",
          spec_names: [],
          unmet_deps: ["rails"])
        sources = build_sources(default: default_source, non_default: [custom_source])
        deps = [build_dep("rails")]
        source_map = described_class.new(sources, deps, [])

        source_map.all_requirements

        expect(default_source).to have_received(:add_dependency_names).with([])
        expect(default_source).to have_received(:add_dependency_names).with("rails")
      end
    end

    context "with empty sources and dependencies" do
      it "returns an empty hash and adds no unmet deps to the default source" do
        default_source = build_source("rubygems")
        allow(default_source).to receive(:add_dependency_names)
        sources = build_sources(default: default_source, non_default: [])
        source_map = described_class.new(sources, [], [])

        result = source_map.all_requirements

        expect(result).to eq({})
        expect(default_source).to have_received(:add_dependency_names).with([])
      end
    end
  end

  describe "pinned source handling" do
    context "when a dependency is pinned to a custom source" do
      let(:default_source) { build_source("rubygems.org") }
      let(:private_source) { build_source("private-gems.example.com", spec_names: [], unmet_deps: []) }
      let(:sources) { build_sources(default: default_source, non_default: [private_source]) }

      before do
        allow(default_source).to receive(:add_dependency_names)
      end

      it "overrides the default source for the pinned dependency" do
        deps = [
          build_dep("my_private_gem", source: private_source),
          build_dep("rails"),
        ]
        source_map = described_class.new(sources, deps, [])

        direct = source_map.direct_requirements

        expect(direct["my_private_gem"]).to eq(private_source)
        expect(direct["rails"]).to eq(default_source)
      end

      it "excludes pinned dependency from pinned_spec_names when its source is skipped" do
        deps = [
          build_dep("my_private_gem", source: private_source),
          build_dep("rails"),
        ]
        source_map = described_class.new(sources, deps, [])

        pinned = source_map.pinned_spec_names(private_source)

        expect(pinned).to include("rails")
        expect(pinned).not_to include("my_private_gem")
      end
    end
  end

  describe "default source resolution" do
    let(:default_source) { build_source("rubygems.org") }
    let(:sources) { build_sources(default: default_source, non_default: []) }

    before do
      allow(default_source).to receive(:add_dependency_names)
    end

    after do
      # State cleanup is handled by RSpec; after block ensures test isolation
    end

    it "uses the default source when a dependency has no explicit source set" do
      deps = [build_dep("rails"), build_dep("pg")]
      source_map = described_class.new(sources, deps, [])

      result = source_map.all_requirements

      expect(result["rails"]).to eq(default_source)
      expect(result["pg"]).to eq(default_source)
    end

    it "includes all default-sourced dependencies in pinned_spec_names with nil skip" do
      deps = [build_dep("rails"), build_dep("pg")]
      source_map = described_class.new(sources, deps, [])

      pinned = source_map.pinned_spec_names(nil)

      expect(pinned).to include("rails", "pg")
      expect(pinned.size).to eq(2)
    end
  end

  describe "integration scenarios" do
    context "a typical Gemfile scenario with default and git sources" do
      let(:default_source) do
        src = build_source("rubygems.org")
        allow(src).to receive(:add_dependency_names)
        src
      end
      let(:git_source) { build_source("git://github.com/rails/rails.git", spec_names: [], unmet_deps: []) }
      let(:sources) { build_sources(default: default_source, non_default: [git_source]) }
      let(:deps) do
        [
          build_dep("rails", source: git_source),
          build_dep("pg"),
          build_dep("puma"),
        ]
      end
      let(:locked) do
        [
          build_locked_spec("rails", git_source),
          build_locked_spec("pg", default_source),
          build_locked_spec("puma", default_source),
        ]
      end

      subject { described_class.new(sources, deps, locked) }

      it "correctly maps direct dependencies to their respective sources" do
        direct = subject.direct_requirements

        expect(direct["rails"]).to eq(git_source)
        expect(direct["pg"]).to eq(default_source)
        expect(direct["puma"]).to eq(default_source)
      end

      it "correctly maps locked specs to their respective sources" do
        locked_reqs = subject.locked_requirements

        expect(locked_reqs["rails"]).to eq(git_source)
        expect(locked_reqs["pg"]).to eq(default_source)
        expect(locked_reqs["puma"]).to eq(default_source)
      end

      it "returns all dependency names when pinning without skip" do
        pinned = subject.pinned_spec_names

        expect(pinned).to include("rails", "pg", "puma")
        expect(pinned.size).to eq(3)
      end

      it "excludes git-sourced dependencies when skipping the git source" do
        pinned_without_git = subject.pinned_spec_names(git_source)

        expect(pinned_without_git).to include("pg", "puma")
        expect(pinned_without_git).not_to include("rails")
      end
    end

    context "all dependencies share the same default source" do
      it "maps every dependency to the default source in all_requirements" do
        default_source = build_source("rubygems.org")
        allow(default_source).to receive(:add_dependency_names)
        sources = build_sources(default: default_source, non_default: [])
        deps = [build_dep("rails"), build_dep("pg")]
        source_map = described_class.new(sources, deps, [])

        result = source_map.all_requirements

        expect(result["rails"]).to eq(default_source)
        expect(result["pg"]).to eq(default_source)
      end
    end
  end
end
