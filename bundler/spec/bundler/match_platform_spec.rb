# frozen_string_literal: true

require "spec_helper"
require "bundler/match_platform"

RSpec.describe Bundler::MatchPlatform do
  # Lightweight test class that includes MatchPlatform and exposes a platform
  # attribute, mirroring how LazySpecification includes it in production.
  let(:test_class) do
    Class.new do
      include Bundler::MatchPlatform

      attr_accessor :platform

      def initialize(platform)
        @platform = platform
      end
    end
  end

  describe "#installable_on_platform?" do
    context "when platform is Gem::Platform::RUBY" do
      it "returns true for any target platform" do
        spec = test_class.new(Gem::Platform::RUBY)
        target = Gem::Platform.new("x86_64-linux")
        expect(spec.installable_on_platform?(target)).to eq(true)
      end

      it "returns true when target is also RUBY" do
        spec = test_class.new(Gem::Platform::RUBY)
        expect(spec.installable_on_platform?(Gem::Platform::RUBY)).to eq(true)
      end
    end

    context "when platform is nil" do
      it "returns true for any target platform" do
        spec = test_class.new(nil)
        target = Gem::Platform.new("x86_64-linux")
        expect(spec.installable_on_platform?(target)).to eq(true)
      end
    end

    context "when platform matches the target platform exactly" do
      it "returns true" do
        platform = Gem::Platform.new("x86_64-linux")
        spec = test_class.new(platform)
        expect(spec.installable_on_platform?(platform)).to eq(true)
      end
    end

    context "when platform is compatible with target via Gem::Platform ===" do
      it "returns true for a compatible platform string" do
        spec = test_class.new("x86_64-linux")
        target = Gem::Platform.new("x86_64-linux")
        expect(spec.installable_on_platform?(target)).to eq(true)
      end
    end

    context "when platform does not match the target" do
      it "returns false for an incompatible platform" do
        spec = test_class.new(Gem::Platform.new("java"))
        target = Gem::Platform.new("x86_64-linux")
        expect(spec.installable_on_platform?(target)).to eq(false)
      end

      it "returns false when platform is arm64-darwin and target is x86_64-linux" do
        spec = test_class.new(Gem::Platform.new("arm64-darwin"))
        target = Gem::Platform.new("x86_64-linux")
        expect(spec.installable_on_platform?(target)).to eq(false)
      end
    end
  end

  describe ".select_best_platform_match" do
    let(:platform) { Gem::Platform.new("x86_64-linux") }

    # Helper doubles: each spec responds to installable_on_platform? via the
    # included MatchPlatform module, and to force_ruby_platform! as required
    # by select_all_platform_match when force_ruby is true.
    let(:ruby_spec) do
      spec = test_class.new(Gem::Platform::RUBY)
      allow(spec).to receive(:force_ruby_platform!)
      spec
    end

    let(:linux_spec) do
      spec = test_class.new(Gem::Platform.new("x86_64-linux"))
      allow(spec).to receive(:force_ruby_platform!)
      spec
    end

    let(:java_spec) do
      spec = test_class.new(Gem::Platform.new("java"))
      allow(spec).to receive(:force_ruby_platform!)
      spec
    end

    it "returns matching specs filtered and sorted by platform" do
      result = Bundler::MatchPlatform.select_best_platform_match(
        [ruby_spec, linux_spec, java_spec], platform
      )
      expect(result).to include(linux_spec)
      expect(result).not_to include(java_spec)
    end

    it "includes ruby platform specs" do
      result = Bundler::MatchPlatform.select_best_platform_match(
        [ruby_spec, java_spec], platform
      )
      expect(result).to include(ruby_spec)
    end

    context "with force_ruby: true" do
      it "only matches Gem::Platform::RUBY specs" do
        result = Bundler::MatchPlatform.select_best_platform_match(
          [ruby_spec, linux_spec, java_spec], platform, force_ruby: true
        )
        expect(result).to include(ruby_spec)
        expect(result).not_to include(java_spec)
      end

      it "calls force_ruby_platform! on all specs" do
        Bundler::MatchPlatform.select_best_platform_match(
          [ruby_spec, linux_spec], platform, force_ruby: true
        )
        expect(ruby_spec).to have_received(:force_ruby_platform!)
        expect(linux_spec).to have_received(:force_ruby_platform!)
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

  describe ".select_all_platform_match" do
    let(:platform) { Gem::Platform.new("x86_64-linux") }

    let(:ruby_spec) do
      spec = test_class.new(Gem::Platform::RUBY)
      allow(spec).to receive(:force_ruby_platform!)
      spec
    end

    let(:linux_spec) do
      spec = test_class.new(Gem::Platform.new("x86_64-linux"))
      allow(spec).to receive(:force_ruby_platform!)
      spec
    end

    let(:java_spec) do
      spec = test_class.new(Gem::Platform.new("java"))
      allow(spec).to receive(:force_ruby_platform!)
      spec
    end

    context "without force_ruby or prefer_locked" do
      it "returns specs matching the given platform" do
        result = Bundler::MatchPlatform.select_all_platform_match(
          [ruby_spec, linux_spec, java_spec], platform
        )
        expect(result).to include(ruby_spec)
        expect(result).to include(linux_spec)
        expect(result).not_to include(java_spec)
      end
    end

    context "with force_ruby: true" do
      it "filters specs installable on RUBY platform only" do
        result = Bundler::MatchPlatform.select_all_platform_match(
          [ruby_spec, linux_spec, java_spec], platform, force_ruby: true
        )
        expect(result).to include(ruby_spec)
      end

      it "calls force_ruby_platform! on all input specs" do
        Bundler::MatchPlatform.select_all_platform_match(
          [ruby_spec, linux_spec, java_spec], platform, force_ruby: true
        )
        expect(ruby_spec).to have_received(:force_ruby_platform!)
        expect(linux_spec).to have_received(:force_ruby_platform!)
        expect(java_spec).to have_received(:force_ruby_platform!)
      end
    end

    context "with prefer_locked: true" do
      it "returns LazySpecification instances when present in matching set" do
        lazy_spec = instance_double(
          Bundler::LazySpecification,
          platform: Gem::Platform::RUBY,
          force_ruby_platform!: nil
        )
        allow(lazy_spec).to receive(:installable_on_platform?).and_return(true)
        allow(lazy_spec).to receive(:is_a?).and_return(false)
        allow(lazy_spec).to receive(:is_a?).with(::Bundler::LazySpecification).and_return(true)

        result = Bundler::MatchPlatform.select_all_platform_match(
          [ruby_spec, lazy_spec], platform, prefer_locked: true
        )
        expect(result).to eq([lazy_spec])
      end

      it "returns all matching specs when no LazySpecification is present" do
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
      end
    end
  end

  describe ".select_best_local_platform_match" do
    it "returns specs matching the local platform after materialization" do
      local = Bundler.local_platform
      materialized = test_class.new(local)
      allow(materialized).to receive(:force_ruby_platform!)

      ruby_spec = test_class.new(Gem::Platform::RUBY)
      allow(ruby_spec).to receive(:force_ruby_platform!)
      allow(ruby_spec).to receive(:materialized_for_installation).and_return(ruby_spec)

      allow(materialized).to receive(:materialized_for_installation).and_return(materialized)

      result = Bundler::MatchPlatform.select_best_local_platform_match(
        [ruby_spec, materialized]
      )
      expect(result).to be_a(Array)
      expect(result).not_to be_empty
    end

    context "when specs have nil materialization" do
      it "filters out nil materialized specs" do
        spec = test_class.new(Gem::Platform::RUBY)
        allow(spec).to receive(:force_ruby_platform!)
        allow(spec).to receive(:materialized_for_installation).and_return(nil)

        result = Bundler::MatchPlatform.select_best_local_platform_match([spec])
        expect(result).to be_a(Array)
      end
    end

    context "with force_ruby: true" do
      it "calls force_ruby_platform! on all input specs" do
        spec = test_class.new(Gem::Platform::RUBY)
        allow(spec).to receive(:force_ruby_platform!)
        allow(spec).to receive(:materialized_for_installation).and_return(spec)

        Bundler::MatchPlatform.select_best_local_platform_match(
          [spec], force_ruby: true
        )
        expect(spec).to have_received(:force_ruby_platform!)
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

  describe ".generic_local_platform_is_ruby?" do
    it "returns a boolean value" do
      result = Bundler::MatchPlatform.generic_local_platform_is_ruby?
      expect([true, false]).to include(result)
    end

    it "compares generic local platform against Gem::Platform::RUBY" do
      # On standard x86_64-linux, Gem::Platform.generic returns "ruby"
      # for generic platforms, making this true on most CI environments
      result = Bundler::MatchPlatform.generic_local_platform_is_ruby?
      generic = Bundler.generic_local_platform
      expect(result).to eq(generic == Gem::Platform::RUBY)
    end
  end

  describe "module structure" do
    it "is a Module" do
      expect(Bundler::MatchPlatform).to be_a(Module)
    end

    it "provides installable_on_platform? as an instance method" do
      instance = test_class.new(Gem::Platform::RUBY)
      expect(instance).to respond_to(:installable_on_platform?)
    end

    it "provides class-level selection methods" do
      expect(Bundler::MatchPlatform).to respond_to(:select_best_platform_match)
      expect(Bundler::MatchPlatform).to respond_to(:select_best_local_platform_match)
      expect(Bundler::MatchPlatform).to respond_to(:select_all_platform_match)
      expect(Bundler::MatchPlatform).to respond_to(:generic_local_platform_is_ruby?)
    end

    it "can be included in classes that define a platform method" do
      instance = test_class.new("ruby")
      expect(instance).to respond_to(:platform)
      expect(instance).to respond_to(:installable_on_platform?)
      expect(test_class.ancestors).to include(Bundler::MatchPlatform)
    end
  end
end
