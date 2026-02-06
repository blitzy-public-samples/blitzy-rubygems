# frozen_string_literal: true

require "spec_helper"
require "bundler/materialization"
require "bundler/match_platform"
require "bundler/lazy_specification"

RSpec.describe Bundler::Materialization do
  # Dependency double providing the interface Materialization expects from the
  # dep argument: #force_ruby_platform, #default_force_ruby_platform, and #name.
  let(:dep) do
    double("dep",
      force_ruby_platform: false,
      default_force_ruby_platform: false,
      name: "test-gem")
  end

  let(:platform) { Gem::Platform::RUBY }

  # A materialized result object returned by a non-missing candidate's
  # #materialization method. Provides #runtime_dependencies for dependency
  # extraction.
  let(:materialized_result) do
    double("materialized_result", runtime_dependencies: [])
  end

  # A candidate spec that is present (not missing) and carries a materialized
  # result. Responds to all methods invoked by MatchPlatform and
  # Materialization: #missing?, #materialization, #runtime_dependencies,
  # #platform, #installable_on_platform?, #force_ruby_platform!.
  let(:present_candidate) do
    double("present_candidate",
      missing?: false,
      materialization: materialized_result,
      runtime_dependencies: [],
      platform: Gem::Platform::RUBY,
      force_ruby_platform!: nil).tap do |c|
      allow(c).to receive(:installable_on_platform?).and_return(true)
      allow(c).to receive(:materialized_for_installation).and_return(c)
    end
  end

  # A candidate spec flagged as missing — simulates a gem that was resolved
  # but could not be found locally or remotely.
  let(:missing_candidate) do
    double("missing_candidate",
      missing?: true,
      materialization: nil,
      runtime_dependencies: [],
      platform: Gem::Platform::RUBY,
      force_ruby_platform!: nil).tap do |c|
      allow(c).to receive(:installable_on_platform?).and_return(true)
      allow(c).to receive(:materialized_for_installation).and_return(c)
    end
  end

  # A second present candidate for multi-spec scenarios.
  let(:second_present_candidate) do
    double("second_present_candidate",
      missing?: false,
      materialization: materialized_result,
      runtime_dependencies: [],
      platform: Gem::Platform::RUBY,
      force_ruby_platform!: nil).tap do |c|
      allow(c).to receive(:installable_on_platform?).and_return(true)
      allow(c).to receive(:materialized_for_installation).and_return(c)
    end
  end

  # ---------------------------------------------------------------------------
  # #initialize
  # ---------------------------------------------------------------------------
  describe "#initialize" do
    it "creates a Materialization instance with dep, platform, and candidates" do
      mat = described_class.new(dep, platform, candidates: [present_candidate])
      expect(mat).to be_a(described_class)
      expect(mat).to respond_to(:complete?)
    end

    it "accepts nil platform" do
      mat = described_class.new(dep, nil, candidates: [present_candidate])
      expect(mat).to be_a(described_class)
      expect(mat).to respond_to(:specs)
    end

    it "accepts nil candidates" do
      mat = described_class.new(dep, platform, candidates: nil)
      expect(mat).to be_a(described_class)
      expect(mat).to respond_to(:completely_missing_specs)
    end

    it "accepts empty candidates array" do
      mat = described_class.new(dep, platform, candidates: [])
      expect(mat).to be_a(described_class)
      expect(mat).to respond_to(:materialized_spec)
    end
  end

  # ---------------------------------------------------------------------------
  # #complete?
  # ---------------------------------------------------------------------------
  describe "#complete?" do
    context "when candidates is nil" do
      it "returns false because specs resolves to an empty array" do
        mat = described_class.new(dep, platform, candidates: nil)
        expect(mat.complete?).to eq(false)
        expect(mat.complete?).to be_falsey
      end
    end

    context "when specs resolve to a non-empty array" do
      it "returns true" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])
        expect(mat.complete?).to eq(true)
        expect(mat.complete?).to be_truthy
      end
    end

    context "when specs resolve to an empty array via platform filtering" do
      it "returns false" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([])
        expect(mat.complete?).to eq(false)
        expect(mat.complete?).to be_falsey
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #specs
  # ---------------------------------------------------------------------------
  describe "#specs" do
    context "when candidates is nil" do
      it "returns an empty array without invoking MatchPlatform" do
        mat = described_class.new(dep, platform, candidates: nil)
        result = mat.specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "when platform is provided (non-nil)" do
      it "delegates to MatchPlatform.select_best_platform_match with the given platform" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .with([present_candidate], platform, force_ruby: false)
          .and_return([present_candidate])

        result = mat.specs
        expect(result).to eq([present_candidate])
        expect(Bundler::MatchPlatform).to have_received(:select_best_platform_match)
      end

      it "passes force_ruby from dep.force_ruby_platform" do
        force_dep = double("force_dep",
          force_ruby_platform: true,
          default_force_ruby_platform: false,
          name: "forced-gem")
        mat = described_class.new(force_dep, platform, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .with([present_candidate], platform, force_ruby: true)
          .and_return([present_candidate])

        result = mat.specs
        expect(result).to eq([present_candidate])
        expect(Bundler::MatchPlatform).to have_received(:select_best_platform_match)
          .with([present_candidate], platform, force_ruby: true)
      end
    end

    context "when platform is nil" do
      it "delegates to MatchPlatform.select_best_local_platform_match" do
        mat = described_class.new(dep, nil, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_local_platform_match)
          .with([present_candidate], force_ruby: false)
          .and_return([present_candidate])

        result = mat.specs
        expect(result).to eq([present_candidate])
        expect(Bundler::MatchPlatform).to have_received(:select_best_local_platform_match)
      end

      it "uses dep.force_ruby_platform OR dep.default_force_ruby_platform" do
        default_force_dep = double("default_force_dep",
          force_ruby_platform: false,
          default_force_ruby_platform: true,
          name: "default-forced-gem")
        mat = described_class.new(default_force_dep, nil, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_local_platform_match)
          .with([present_candidate], force_ruby: true)
          .and_return([present_candidate])

        result = mat.specs
        expect(result).to eq([present_candidate])
        expect(Bundler::MatchPlatform).to have_received(:select_best_local_platform_match)
          .with([present_candidate], force_ruby: true)
      end
    end

    context "memoization" do
      it "caches the result on subsequent calls" do
        mat = described_class.new(dep, platform, candidates: nil)
        first_result = mat.specs
        second_result = mat.specs
        expect(first_result).to equal(second_result)
        expect(first_result).to eq([])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #materialized_spec
  # ---------------------------------------------------------------------------
  describe "#materialized_spec" do
    context "when all specs are present (not missing)" do
      it "returns the materialization of the first non-missing spec" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])

        result = mat.materialized_spec
        expect(result).to eq(materialized_result)
        expect(result).not_to be_nil
      end
    end

    context "when the first spec is missing but a later spec is present" do
      it "returns the materialization of the first non-missing spec" do
        mat = described_class.new(dep, platform, candidates: [missing_candidate, present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate, present_candidate])

        result = mat.materialized_spec
        expect(result).to eq(materialized_result)
        expect(result).not_to be_nil
      end
    end

    context "when all specs are missing" do
      it "returns nil" do
        mat = described_class.new(dep, platform, candidates: [missing_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate])

        result = mat.materialized_spec
        expect(result).to be_nil
      end
    end

    context "when candidates is nil (no specs)" do
      it "returns nil" do
        mat = described_class.new(dep, platform, candidates: nil)
        result = mat.materialized_spec
        expect(result).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #completely_missing_specs
  # ---------------------------------------------------------------------------
  describe "#completely_missing_specs" do
    context "when all specs are missing" do
      it "returns the full list of specs" do
        mat = described_class.new(dep, platform, candidates: [missing_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate])

        result = mat.completely_missing_specs
        expect(result).to eq([missing_candidate])
        expect(result.length).to eq(1)
      end
    end

    context "when some specs are present and some are missing" do
      it "returns an empty array because not all specs are missing" do
        mat = described_class.new(dep, platform, candidates: [present_candidate, missing_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate, missing_candidate])

        result = mat.completely_missing_specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "when no specs are missing" do
      it "returns an empty array" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])

        result = mat.completely_missing_specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "when candidates is nil (no specs)" do
      it "returns an empty array since the empty specs list passes all?(&:missing?)" do
        mat = described_class.new(dep, platform, candidates: nil)
        # specs returns [], and [].all?(&:missing?) is true (vacuous truth),
        # so completely_missing_specs returns the empty specs array.
        result = mat.completely_missing_specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "with multiple missing specs" do
      let(:another_missing) do
        double("another_missing",
          missing?: true,
          materialization: nil,
          runtime_dependencies: [],
          platform: Gem::Platform::RUBY,
          force_ruby_platform!: nil).tap do |c|
          allow(c).to receive(:installable_on_platform?).and_return(true)
          allow(c).to receive(:materialized_for_installation).and_return(c)
        end
      end

      it "returns all missing specs" do
        mat = described_class.new(dep, platform, candidates: [missing_candidate, another_missing])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate, another_missing])

        result = mat.completely_missing_specs
        expect(result).to eq([missing_candidate, another_missing])
        expect(result.length).to eq(2)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #partially_missing_specs
  # ---------------------------------------------------------------------------
  describe "#partially_missing_specs" do
    context "when some specs are missing and some are present" do
      it "returns only the missing specs" do
        mat = described_class.new(dep, platform, candidates: [present_candidate, missing_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate, missing_candidate])

        result = mat.partially_missing_specs
        expect(result).to eq([missing_candidate])
        expect(result.length).to eq(1)
      end
    end

    context "when no specs are missing" do
      it "returns an empty array" do
        mat = described_class.new(dep, platform, candidates: [present_candidate, second_present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate, second_present_candidate])

        result = mat.partially_missing_specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "when all specs are missing" do
      it "returns all specs" do
        mat = described_class.new(dep, platform, candidates: [missing_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate])

        result = mat.partially_missing_specs
        expect(result).to eq([missing_candidate])
        expect(result.length).to eq(1)
      end
    end

    context "when candidates is nil (no specs)" do
      it "returns an empty array" do
        mat = described_class.new(dep, platform, candidates: nil)
        result = mat.partially_missing_specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #incomplete_specs
  # ---------------------------------------------------------------------------
  describe "#incomplete_specs" do
    context "when materialization is complete (specs non-empty)" do
      it "returns an empty array" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])

        result = mat.incomplete_specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "when materialization is incomplete and candidates exist" do
      it "returns the candidates array" do
        candidates = [present_candidate]
        mat = described_class.new(dep, platform, candidates: candidates)
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([])

        result = mat.incomplete_specs
        expect(result).to eq(candidates)
        expect(result).not_to be_empty
      end
    end

    context "when materialization is incomplete and candidates is nil" do
      it "returns a new LazySpecification with the dep name" do
        mat = described_class.new(dep, platform, candidates: nil)
        result = mat.incomplete_specs

        expect(result).to be_a(Bundler::LazySpecification)
        expect(result.name).to eq("test-gem")
      end

      it "returns a LazySpecification with nil version and nil platform" do
        mat = described_class.new(dep, platform, candidates: nil)
        result = mat.incomplete_specs

        expect(result.version).to be_nil
        expect(result.platform).to eq(Gem::Platform::RUBY)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #dependencies
  # ---------------------------------------------------------------------------
  describe "#dependencies" do
    context "when materialized_spec is available" do
      let(:runtime_dep) { double("runtime_dep") }
      let(:rich_materialized_result) do
        double("rich_materialized_result", runtime_dependencies: [runtime_dep])
      end
      let(:rich_present_candidate) do
        double("rich_present_candidate",
          missing?: false,
          materialization: rich_materialized_result,
          runtime_dependencies: [runtime_dep],
          platform: Gem::Platform::RUBY,
          force_ruby_platform!: nil).tap do |c|
          allow(c).to receive(:installable_on_platform?).and_return(true)
          allow(c).to receive(:materialized_for_installation).and_return(c)
        end
      end

      it "returns runtime_dependencies mapped with the platform" do
        mat = described_class.new(dep, platform, candidates: [rich_present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([rich_present_candidate])

        result = mat.dependencies
        expect(result).to eq([[runtime_dep, platform]])
        expect(result.length).to eq(1)
      end

      it "returns each dependency paired with the materialization platform" do
        dep2 = double("runtime_dep2")
        multi_dep_materialized = double("multi_dep_materialized",
          runtime_dependencies: [runtime_dep, dep2])
        multi_dep_candidate = double("multi_dep_candidate",
          missing?: false,
          materialization: multi_dep_materialized,
          runtime_dependencies: [runtime_dep, dep2],
          platform: Gem::Platform::RUBY,
          force_ruby_platform!: nil).tap do |c|
          allow(c).to receive(:installable_on_platform?).and_return(true)
          allow(c).to receive(:materialized_for_installation).and_return(c)
        end

        mat = described_class.new(dep, platform, candidates: [multi_dep_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([multi_dep_candidate])

        result = mat.dependencies
        expect(result).to eq([[runtime_dep, platform], [dep2, platform]])
        expect(result.length).to eq(2)
      end
    end

    context "when materialized_spec is nil (all specs missing)" do
      let(:runtime_dep) { double("runtime_dep") }
      let(:missing_with_deps) do
        double("missing_with_deps",
          missing?: true,
          materialization: nil,
          runtime_dependencies: [runtime_dep],
          platform: Gem::Platform::RUBY,
          force_ruby_platform!: nil).tap do |c|
          allow(c).to receive(:installable_on_platform?).and_return(true)
          allow(c).to receive(:materialized_for_installation).and_return(c)
        end
      end

      it "falls back to specs.first for runtime_dependencies" do
        mat = described_class.new(dep, platform, candidates: [missing_with_deps])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_with_deps])

        result = mat.dependencies
        expect(result).to eq([[runtime_dep, platform]])
        expect(result.first.first).to eq(runtime_dep)
      end
    end

    context "when there are no runtime dependencies" do
      it "returns an empty array" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])

        result = mat.dependencies
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "with nil platform" do
      let(:runtime_dep) { double("runtime_dep") }
      let(:rich_materialized_result) do
        double("rich_materialized_result", runtime_dependencies: [runtime_dep])
      end
      let(:rich_present_candidate) do
        double("rich_present_candidate",
          missing?: false,
          materialization: rich_materialized_result,
          runtime_dependencies: [runtime_dep],
          platform: Gem::Platform::RUBY,
          force_ruby_platform!: nil).tap do |c|
          allow(c).to receive(:installable_on_platform?).and_return(true)
          allow(c).to receive(:materialized_for_installation).and_return(c)
        end
      end

      it "pairs each dependency with nil platform" do
        mat = described_class.new(dep, nil, candidates: [rich_present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_local_platform_match)
          .and_return([rich_present_candidate])

        result = mat.dependencies
        expect(result).to eq([[runtime_dep, nil]])
        expect(result.first.last).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases and integration scenarios
  # ---------------------------------------------------------------------------
  describe "edge cases" do
    context "when candidates is an empty array" do
      it "specs returns empty via MatchPlatform filtering" do
        mat = described_class.new(dep, platform, candidates: [])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([])

        expect(mat.specs).to eq([])
        expect(mat.complete?).to eq(false)
      end
    end

    context "interaction between complete? and incomplete_specs" do
      it "incomplete_specs returns empty when complete? is true" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])

        expect(mat.complete?).to eq(true)
        expect(mat.incomplete_specs).to eq([])
      end

      it "incomplete_specs returns candidates when complete? is false" do
        candidates = [present_candidate]
        mat = described_class.new(dep, platform, candidates: candidates)
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([])

        expect(mat.complete?).to eq(false)
        expect(mat.incomplete_specs).to eq(candidates)
      end
    end

    context "interaction between materialized_spec and completely_missing_specs" do
      it "materialized_spec is nil when completely_missing_specs returns all specs" do
        mat = described_class.new(dep, platform, candidates: [missing_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate])

        expect(mat.materialized_spec).to be_nil
        expect(mat.completely_missing_specs).to eq([missing_candidate])
      end

      it "materialized_spec is present when completely_missing_specs returns empty" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])

        expect(mat.materialized_spec).to eq(materialized_result)
        expect(mat.completely_missing_specs).to eq([])
      end
    end

    context "with mixed missing and present specs" do
      it "partially_missing_specs returns missing specs while materialized_spec returns the first present" do
        mat = described_class.new(dep, platform,
          candidates: [present_candidate, missing_candidate])
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate, missing_candidate])

        expect(mat.partially_missing_specs).to eq([missing_candidate])
        expect(mat.materialized_spec).to eq(materialized_result)
        expect(mat.completely_missing_specs).to eq([])
      end
    end
  end
end
