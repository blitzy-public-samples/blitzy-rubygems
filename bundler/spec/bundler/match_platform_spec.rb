# frozen_string_literal: true

require "spec_helper"
require "bundler/match_platform"

RSpec.describe Bundler::MatchPlatform do
  # Lightweight test class that includes MatchPlatform and exposes a platform
  # accessor, mirroring how LazySpecification and other production classes
  # include the module to gain platform matching behavior.
  let(:test_class) do
    Class.new do
      include Bundler::MatchPlatform

      attr_accessor :platform

      def initialize(platform)
        @platform = platform
      end
    end
  end

  # Creates a spec instance from test_class with stub methods required by
  # class-level selection helpers (force_ruby_platform!, materialized_for_installation).
  # These are NOT MatchPlatform methods — they belong to ForcePlatform and
  # LazySpecification respectively, so stubbing them is permitted.
  def build_spec(platform, materialized: :self)
    spec = test_class.new(platform)
    allow(spec).to receive(:force_ruby_platform!)
    mat_value = materialized == :self ? spec : materialized
    allow(spec).to receive(:materialized_for_installation).and_return(mat_value)
    spec
  end

  # ---------------------------------------------------------------------------
  # Instance method: #installable_on_platform?
  # ---------------------------------------------------------------------------

  describe "#installable_on_platform?" do
    context "when platform is Gem::Platform::RUBY" do
      it "returns true for a specific architecture target" do
        spec = test_class.new(Gem::Platform::RUBY)
        target = Gem::Platform.new("x86_64-linux")

        result = spec.installable_on_platform?(target)

        expect(result).to eq(true)
        expect(spec.platform).to eq(Gem::Platform::RUBY)
      end

      it "returns true when target is also Gem::Platform::RUBY" do
        spec = test_class.new(Gem::Platform::RUBY)

        result = spec.installable_on_platform?(Gem::Platform::RUBY)

        expect(result).to eq(true)
        expect(result).to be_truthy
      end
    end

    context "when platform is nil" do
      it "returns true for any target platform" do
        spec = test_class.new(nil)
        target = Gem::Platform.new("x86_64-linux")

        result = spec.installable_on_platform?(target)

        expect(result).to eq(true)
        expect(spec.platform).to be_nil
      end
    end

    context "when platform matches the target platform exactly" do
      it "returns true for an identical Gem::Platform object" do
        platform = Gem::Platform.new("x86_64-linux")
        spec = test_class.new(platform)

        result = spec.installable_on_platform?(platform)

        expect(result).to eq(true)
        expect(spec.platform).to eq(platform)
      end
    end

    context "when platform is compatible via Gem::Platform ===" do
      it "returns true for a string that matches the target platform" do
        spec = test_class.new("x86_64-linux")
        target = Gem::Platform.new("x86_64-linux")

        result = spec.installable_on_platform?(target)

        expect(result).to eq(true)
        expect(result).to be_a(TrueClass)
      end
    end

    context "when platform does not match the target" do
      it "returns false for a java platform against a linux target" do
        spec = test_class.new(Gem::Platform.new("java"))
        target = Gem::Platform.new("x86_64-linux")

        result = spec.installable_on_platform?(target)

        expect(result).to eq(false)
        expect(result).to be_falsey
      end

      it "returns false for cross-architecture mismatch" do
        spec = test_class.new(Gem::Platform.new("arm64-darwin"))
        target = Gem::Platform.new("x86_64-linux")

        result = spec.installable_on_platform?(target)

        expect(result).to eq(false)
        expect(result).to be_a(FalseClass)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Class method: .select_best_platform_match
  # ---------------------------------------------------------------------------

  describe ".select_best_platform_match" do
    let(:platform) { Gem::Platform.new("x86_64-linux") }

    it "returns matching specs filtered and sorted, excluding non-matching" do
      ruby_spec = build_spec(Gem::Platform::RUBY)
      linux_spec = build_spec(Gem::Platform.new("x86_64-linux"))
      java_spec = build_spec(Gem::Platform.new("java"))

      result = Bundler::MatchPlatform.select_best_platform_match(
        [ruby_spec, linux_spec, java_spec], platform
      )

      expect(result).to include(linux_spec)
      expect(result).not_to include(java_spec)
    end

    it "includes ruby platform specs when they are the only match" do
      ruby_spec = build_spec(Gem::Platform::RUBY)
      java_spec = build_spec(Gem::Platform.new("java"))

      result = Bundler::MatchPlatform.select_best_platform_match(
        [ruby_spec, java_spec], platform
      )

      expect(result).to include(ruby_spec)
      expect(result).not_to include(java_spec)
    end

    context "with force_ruby: true" do
      it "calls force_ruby_platform! on all input specs" do
        ruby_spec = build_spec(Gem::Platform::RUBY)
        linux_spec = build_spec(Gem::Platform.new("x86_64-linux"))

        Bundler::MatchPlatform.select_best_platform_match(
          [ruby_spec, linux_spec], platform, force_ruby: true
        )

        expect(ruby_spec).to have_received(:force_ruby_platform!)
        expect(linux_spec).to have_received(:force_ruby_platform!)
      end

      it "returns only RUBY-installable specs in result" do
        ruby_spec = build_spec(Gem::Platform::RUBY)
        java_spec = build_spec(Gem::Platform.new("java"))

        result = Bundler::MatchPlatform.select_best_platform_match(
          [ruby_spec, java_spec], platform, force_ruby: true
        )

        expect(result).to include(ruby_spec)
        expect(result).not_to include(java_spec)
      end
    end

    context "with empty specs array" do
      it "returns an empty array" do
        result = Bundler::MatchPlatform.select_best_platform_match([], platform)

        expect(result).to be_empty
        expect(result).to be_a(Array)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Class method: .select_all_platform_match
  # ---------------------------------------------------------------------------

  describe ".select_all_platform_match" do
    let(:platform) { Gem::Platform.new("x86_64-linux") }

    context "without force_ruby or prefer_locked" do
      it "returns all specs matching the given platform" do
        ruby_spec = build_spec(Gem::Platform::RUBY)
        linux_spec = build_spec(Gem::Platform.new("x86_64-linux"))
        java_spec = build_spec(Gem::Platform.new("java"))

        result = Bundler::MatchPlatform.select_all_platform_match(
          [ruby_spec, linux_spec, java_spec], platform
        )

        expect(result).to include(ruby_spec)
        expect(result).to include(linux_spec)
        expect(result).not_to include(java_spec)
      end
    end

    context "with force_ruby: true" do
      it "filters to RUBY-installable specs and calls force_ruby_platform! on all" do
        ruby_spec = build_spec(Gem::Platform::RUBY)
        linux_spec = build_spec(Gem::Platform.new("x86_64-linux"))
        java_spec = build_spec(Gem::Platform.new("java"))

        result = Bundler::MatchPlatform.select_all_platform_match(
          [ruby_spec, linux_spec, java_spec], platform, force_ruby: true
        )

        expect(result).to include(ruby_spec)
        expect(ruby_spec).to have_received(:force_ruby_platform!)
        expect(linux_spec).to have_received(:force_ruby_platform!)
        expect(java_spec).to have_received(:force_ruby_platform!)
      end
    end

    context "with prefer_locked: true" do
      it "returns only LazySpecification instances when present in matching set" do
        lazy_spec = instance_double(
          Bundler::LazySpecification,
          platform: Gem::Platform::RUBY,
          force_ruby_platform!: nil
        )
        allow(lazy_spec).to receive(:installable_on_platform?).and_return(true)
        allow(lazy_spec).to receive(:is_a?).and_return(false)
        allow(lazy_spec).to receive(:is_a?).with(::Bundler::LazySpecification).and_return(true)

        ruby_spec = build_spec(Gem::Platform::RUBY)

        result = Bundler::MatchPlatform.select_all_platform_match(
          [ruby_spec, lazy_spec], platform, prefer_locked: true
        )

        expect(result).to eq([lazy_spec])
        expect(result.length).to eq(1)
      end

      it "returns all matching specs when no LazySpecification is present" do
        ruby_spec = build_spec(Gem::Platform::RUBY)
        linux_spec = build_spec(Gem::Platform.new("x86_64-linux"))

        result = Bundler::MatchPlatform.select_all_platform_match(
          [ruby_spec, linux_spec], platform, prefer_locked: true
        )

        expect(result).to include(ruby_spec)
        expect(result).to include(linux_spec)
      end
    end

    context "with empty specs array" do
      it "returns an empty array" do
        result = Bundler::MatchPlatform.select_all_platform_match([], platform)

        expect(result).to be_empty
        expect(result).to be_a(Array)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Class method: .select_best_local_platform_match
  # ---------------------------------------------------------------------------

  describe ".select_best_local_platform_match" do
    it "returns specs matching the local platform after materialization" do
      spec = build_spec(Gem::Platform::RUBY)

      result = Bundler::MatchPlatform.select_best_local_platform_match([spec])

      expect(result).to be_a(Array)
      expect(result).not_to be_empty
    end

    context "when specs have nil materialization" do
      it "filters out specs whose materialized_for_installation returns nil" do
        spec = build_spec(Gem::Platform::RUBY, materialized: nil)

        result = Bundler::MatchPlatform.select_best_local_platform_match([spec])

        expect(result).to be_a(Array)
        expect(result).to be_empty
      end
    end

    context "with force_ruby: true" do
      it "calls force_ruby_platform! on all specs and materializes them" do
        spec = build_spec(Gem::Platform::RUBY)

        Bundler::MatchPlatform.select_best_local_platform_match(
          [spec], force_ruby: true
        )

        expect(spec).to have_received(:force_ruby_platform!)
        expect(spec).to have_received(:materialized_for_installation)
      end
    end

    context "with empty specs array" do
      it "returns an empty array" do
        result = Bundler::MatchPlatform.select_best_local_platform_match([])

        expect(result).to be_empty
        expect(result).to be_a(Array)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Class method: .generic_local_platform_is_ruby?
  # ---------------------------------------------------------------------------

  describe ".generic_local_platform_is_ruby?" do
    it "returns a boolean consistent with Bundler.generic_local_platform" do
      result = Bundler::MatchPlatform.generic_local_platform_is_ruby?
      generic = Bundler.generic_local_platform

      expect([true, false]).to include(result)
      expect(result).to eq(generic == Gem::Platform::RUBY)
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  context "edge cases" do
    it "handles exotic platform strings in installable_on_platform?" do
      spec = test_class.new("x86_64-linux-musl")
      target = Gem::Platform.new("x86_64-linux")

      result = spec.installable_on_platform?(target)

      expect([true, false]).to include(result)
      expect(spec.platform).to eq("x86_64-linux-musl")
    end

    it "treats the string 'ruby' identically to Gem::Platform::RUBY" do
      spec_string = test_class.new("ruby")
      spec_const = test_class.new(Gem::Platform::RUBY)
      target = Gem::Platform.new("x86_64-linux")

      result_string = spec_string.installable_on_platform?(target)
      result_const = spec_const.installable_on_platform?(target)

      expect(result_string).to eq(result_const)
      expect(result_string).to eq(true)
    end

    it "returns consistent results for select_all_platform_match with single spec" do
      spec = build_spec(Gem::Platform::RUBY)
      platform = Gem::Platform.new("x86_64-linux")

      result = Bundler::MatchPlatform.select_all_platform_match([spec], platform)

      expect(result).to be_a(Array)
      expect(result.length).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Module structure verification
  # ---------------------------------------------------------------------------

  describe "module structure" do
    it "is a Module that provides class-level selection methods" do
      expect(Bundler::MatchPlatform).to be_a(Module)
      expect(Bundler::MatchPlatform).to respond_to(:select_best_platform_match)
      expect(Bundler::MatchPlatform).to respond_to(:select_best_local_platform_match)
      expect(Bundler::MatchPlatform).to respond_to(:select_all_platform_match)
      expect(Bundler::MatchPlatform).to respond_to(:generic_local_platform_is_ruby?)
    end

    it "provides installable_on_platform? as an instance method when included" do
      instance = test_class.new(Gem::Platform::RUBY)

      expect(instance).to respond_to(:installable_on_platform?)
      expect(test_class.ancestors).to include(Bundler::MatchPlatform)
    end
  end
end
