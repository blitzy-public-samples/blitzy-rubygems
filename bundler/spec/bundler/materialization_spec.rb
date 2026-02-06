# frozen_string_literal: true

require "spec_helper"
require "bundler/materialization"

RSpec.describe Bundler::Materialization do
  # ---------------------------------------------------------------------------
  # Shared doubles — these model the interfaces Materialization interacts with
  # ---------------------------------------------------------------------------

  # Dependency double providing the interface Materialization expects:
  # #force_ruby_platform, #default_force_ruby_platform, #name
  let(:dep) do
    double("dep",
      force_ruby_platform: false,
      default_force_ruby_platform: false,
      name: "test-gem")
  end

  let(:platform) { Gem::Platform::RUBY }

  # A materialized result object returned by a non-missing candidate's
  # #materialization method. Provides #runtime_dependencies for dependency
  # extraction in the #dependencies method.
  let(:materialized_result) do
    double("materialized_result", runtime_dependencies: [])
  end

  # A candidate spec that is present (not missing) and carries a materialized
  # result. Responds to all methods invoked by MatchPlatform selection and
  # Materialization inspection.
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

  # A second present candidate used in multi-spec scenarios.
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
      subject = described_class.new(dep, platform, candidates: [present_candidate])
      expect(subject).to be_a(described_class)
      expect(subject).to respond_to(:complete?)
      expect(subject).to respond_to(:specs)
    end

    it "accepts nil platform for local platform resolution" do
      subject = described_class.new(dep, nil, candidates: [present_candidate])
      expect(subject).to be_a(described_class)
      expect(subject).to respond_to(:materialized_spec)
    end

    it "accepts nil candidates indicating no resolved specifications" do
      subject = described_class.new(dep, platform, candidates: nil)
      expect(subject).to be_a(described_class)
      expect(subject).to respond_to(:completely_missing_specs)
    end

    it "accepts an empty candidates array" do
      subject = described_class.new(dep, platform, candidates: [])
      expect(subject).to be_a(described_class)
      expect(subject).to respond_to(:incomplete_specs)
    end
  end

  # ---------------------------------------------------------------------------
  # #complete?
  # ---------------------------------------------------------------------------
  describe "#complete?" do
    context "when candidates is nil" do
      subject { described_class.new(dep, platform, candidates: nil) }

      it "returns false because specs resolves to an empty array" do
        expect(subject.complete?).to eq(false)
        expect(subject.complete?).to be_falsey
      end
    end

    context "when specs resolve to a non-empty array" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])
      end

      subject { described_class.new(dep, platform, candidates: [present_candidate]) }

      it "returns true" do
        expect(subject.complete?).to eq(true)
        expect(subject.complete?).to be_truthy
      end
    end

    context "when specs resolve to an empty array via platform filtering" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([])
      end

      subject { described_class.new(dep, platform, candidates: [present_candidate]) }

      it "returns false" do
        expect(subject.complete?).to eq(false)
        expect(subject.complete?).to be_falsey
      end
    end

    context "when candidates is an empty array" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([])
      end

      subject { described_class.new(dep, platform, candidates: []) }

      it "returns false" do
        expect(subject.complete?).to eq(false)
        expect(subject.complete?).to be_falsey
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #specs
  # ---------------------------------------------------------------------------
  describe "#specs" do
    context "when candidates is nil" do
      subject { described_class.new(dep, platform, candidates: nil) }

      it "returns an empty array without invoking MatchPlatform" do
        result = subject.specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "when platform is provided (non-nil)" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .with([present_candidate], platform, force_ruby: false)
          .and_return([present_candidate])
      end

      it "delegates to MatchPlatform.select_best_platform_match with the given platform" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        result = mat.specs
        expect(result).to eq([present_candidate])
        expect(Bundler::MatchPlatform).to have_received(:select_best_platform_match)
      end

      it "passes force_ruby: true when dep.force_ruby_platform is true" do
        force_dep = double("force_dep",
          force_ruby_platform: true,
          default_force_ruby_platform: false,
          name: "forced-gem")
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .with([present_candidate], platform, force_ruby: true)
          .and_return([present_candidate])

        mat = described_class.new(force_dep, platform, candidates: [present_candidate])
        result = mat.specs
        expect(result).to eq([present_candidate])
        expect(Bundler::MatchPlatform).to have_received(:select_best_platform_match)
          .with([present_candidate], platform, force_ruby: true)
      end
    end

    context "when platform is nil (local platform resolution)" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_local_platform_match)
          .with([present_candidate], force_ruby: false)
          .and_return([present_candidate])
      end

      it "delegates to MatchPlatform.select_best_local_platform_match" do
        mat = described_class.new(dep, nil, candidates: [present_candidate])
        result = mat.specs
        expect(result).to eq([present_candidate])
        expect(Bundler::MatchPlatform).to have_received(:select_best_local_platform_match)
      end

      it "uses dep.default_force_ruby_platform when force_ruby_platform is false" do
        default_force_dep = double("default_force_dep",
          force_ruby_platform: false,
          default_force_ruby_platform: true,
          name: "default-forced-gem")
        allow(Bundler::MatchPlatform).to receive(:select_best_local_platform_match)
          .with([present_candidate], force_ruby: true)
          .and_return([present_candidate])

        mat = described_class.new(default_force_dep, nil, candidates: [present_candidate])
        result = mat.specs
        expect(result).to eq([present_candidate])
        expect(Bundler::MatchPlatform).to have_received(:select_best_local_platform_match)
          .with([present_candidate], force_ruby: true)
      end
    end

    context "memoization" do
      subject { described_class.new(dep, platform, candidates: nil) }

      it "caches the result on subsequent calls" do
        first_result = subject.specs
        second_result = subject.specs
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
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])
      end

      it "returns the materialization of the first non-missing spec" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        result = mat.materialized_spec
        expect(result).to eq(materialized_result)
        expect(result).not_to be_nil
      end
    end

    context "when the first spec is missing but a later spec is present" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate, present_candidate])
      end

      it "skips missing specs and returns the first non-missing materialization" do
        mat = described_class.new(dep, platform,
          candidates: [missing_candidate, present_candidate])
        result = mat.materialized_spec
        expect(result).to eq(materialized_result)
        expect(result).not_to be_nil
      end
    end

    context "when all specs are missing" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate])
      end

      it "returns nil" do
        mat = described_class.new(dep, platform, candidates: [missing_candidate])
        result = mat.materialized_spec
        expect(result).to be_nil
      end
    end

    context "when candidates is nil (no specs)" do
      it "returns nil because specs is empty" do
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
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate])
      end

      it "returns the full list of specs" do
        mat = described_class.new(dep, platform, candidates: [missing_candidate])
        result = mat.completely_missing_specs
        expect(result).to eq([missing_candidate])
        expect(result).to include(missing_candidate)
      end
    end

    context "when some specs are present and some are missing" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate, missing_candidate])
      end

      it "returns an empty array because not all specs are missing" do
        mat = described_class.new(dep, platform,
          candidates: [present_candidate, missing_candidate])
        result = mat.completely_missing_specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "when no specs are missing" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])
      end

      it "returns an empty array" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        result = mat.completely_missing_specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "when candidates is nil (no specs)" do
      it "returns empty array since empty specs vacuously satisfy all?(&:missing?)" do
        mat = described_class.new(dep, platform, candidates: nil)
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

      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate, another_missing])
      end

      it "returns all missing specs" do
        mat = described_class.new(dep, platform,
          candidates: [missing_candidate, another_missing])
        result = mat.completely_missing_specs
        expect(result).to include(missing_candidate, another_missing)
        expect(result.length).to eq(2)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #partially_missing_specs
  # ---------------------------------------------------------------------------
  describe "#partially_missing_specs" do
    context "when some specs are missing and some are present" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate, missing_candidate])
      end

      it "returns only the missing specs" do
        mat = described_class.new(dep, platform,
          candidates: [present_candidate, missing_candidate])
        result = mat.partially_missing_specs
        expect(result).to eq([missing_candidate])
        expect(result).to include(missing_candidate)
      end
    end

    context "when no specs are missing" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate, second_present_candidate])
      end

      it "returns an empty array" do
        mat = described_class.new(dep, platform,
          candidates: [present_candidate, second_present_candidate])
        result = mat.partially_missing_specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "when all specs are missing" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate])
      end

      it "returns all specs since all are missing" do
        mat = described_class.new(dep, platform, candidates: [missing_candidate])
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
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])
      end

      it "returns an empty array" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        result = mat.incomplete_specs
        expect(result).to eq([])
        expect(result).to be_empty
      end
    end

    context "when materialization is incomplete and candidates array exists" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([])
      end

      it "returns the candidates array" do
        candidates = [present_candidate]
        mat = described_class.new(dep, platform, candidates: candidates)
        result = mat.incomplete_specs
        expect(result).to eq(candidates)
        expect(result).to include(present_candidate)
      end
    end

    context "when materialization is incomplete and candidates is nil" do
      it "returns a new LazySpecification with the dep name" do
        mat = described_class.new(dep, platform, candidates: nil)
        result = mat.incomplete_specs
        expect(result).to be_a(Bundler::LazySpecification)
        expect(result.name).to eq("test-gem")
      end

      it "returns a LazySpecification with nil version and RUBY platform default" do
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

      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([rich_present_candidate])
      end

      it "returns runtime_dependencies mapped with the platform" do
        mat = described_class.new(dep, platform, candidates: [rich_present_candidate])
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
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([multi_dep_candidate])

        mat = described_class.new(dep, platform, candidates: [multi_dep_candidate])
        result = mat.dependencies
        expect(result).to include([runtime_dep, platform])
        expect(result).to include([dep2, platform])
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

      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_with_deps])
      end

      it "falls back to specs.first for runtime_dependencies" do
        mat = described_class.new(dep, platform, candidates: [missing_with_deps])
        result = mat.dependencies
        expect(result).to eq([[runtime_dep, platform]])
        expect(result.first.first).to eq(runtime_dep)
      end
    end

    context "when there are no runtime dependencies" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])
      end

      it "returns an empty array" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
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

      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_local_platform_match)
          .and_return([rich_present_candidate])
      end

      it "pairs each dependency with nil platform" do
        mat = described_class.new(dep, nil, candidates: [rich_present_candidate])
        result = mat.dependencies
        expect(result).to eq([[runtime_dep, nil]])
        expect(result.first.last).to be_nil
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Missing gem detection scenarios
  # ---------------------------------------------------------------------------
  context "missing gem error scenarios" do
    context "when all candidates are missing" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([missing_candidate])
      end

      it "completely_missing_specs returns the full list and materialized_spec is nil" do
        mat = described_class.new(dep, platform, candidates: [missing_candidate])
        expect(mat.completely_missing_specs).to eq([missing_candidate])
        expect(mat.materialized_spec).to be_nil
      end

      it "partially_missing_specs also contains all missing candidates" do
        mat = described_class.new(dep, platform, candidates: [missing_candidate])
        expect(mat.partially_missing_specs).to include(missing_candidate)
        expect(mat.partially_missing_specs.length).to eq(1)
      end
    end

    context "when mixed missing and present specs exist" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate, missing_candidate])
      end

      it "partially_missing_specs returns only missing while materialized_spec is present" do
        mat = described_class.new(dep, platform,
          candidates: [present_candidate, missing_candidate])
        expect(mat.partially_missing_specs).to eq([missing_candidate])
        expect(mat.materialized_spec).to eq(materialized_result)
        expect(mat.completely_missing_specs).to eq([])
      end
    end

    context "when candidates is nil indicating unresolved gem" do
      it "reports incomplete and has no completely missing specs" do
        mat = described_class.new(dep, platform, candidates: nil)
        expect(mat.complete?).to be_falsey
        expect(mat.completely_missing_specs).to be_empty
      end

      it "returns a LazySpecification placeholder from incomplete_specs" do
        mat = described_class.new(dep, platform, candidates: nil)
        result = mat.incomplete_specs
        expect(result).to be_a(Bundler::LazySpecification)
        expect(result.name).to eq("test-gem")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Integration between complete? and incomplete_specs
  # ---------------------------------------------------------------------------
  context "interaction between complete? and incomplete_specs" do
    context "when complete" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([present_candidate])
      end

      it "incomplete_specs returns empty when complete? is true" do
        mat = described_class.new(dep, platform, candidates: [present_candidate])
        expect(mat.complete?).to eq(true)
        expect(mat.incomplete_specs).to eq([])
      end
    end

    context "when incomplete with candidates" do
      before do
        allow(Bundler::MatchPlatform).to receive(:select_best_platform_match)
          .and_return([])
      end

      it "incomplete_specs returns candidates when complete? is false" do
        candidates = [present_candidate]
        mat = described_class.new(dep, platform, candidates: candidates)
        expect(mat.complete?).to eq(false)
        expect(mat.incomplete_specs).to eq(candidates)
      end
    end
  end
end
