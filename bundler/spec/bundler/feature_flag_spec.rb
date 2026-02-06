# frozen_string_literal: true

require "spec_helper"
require "bundler/feature_flag"

RSpec.describe Bundler::FeatureFlag do
  describe "#initialize" do
    it "stores the bundler version as a Gem::Version" do
      flag = described_class.new("2.5.0")
      expect(flag).to be_a(Bundler::FeatureFlag)
    end

    it "accepts a string version" do
      flag = described_class.new("3.1.2")
      expect(flag.bundler_3_mode?).to eq(true)
      expect(flag.bundler_4_mode?).to eq(false)
    end

    it "accepts a Gem::Version object" do
      version = Gem::Version.new("4.0.0")
      flag = described_class.new(version)
      expect(flag.bundler_4_mode?).to eq(true)
      expect(flag.bundler_5_mode?).to eq(false)
    end

    it "correctly extracts the major version from a pre-release version" do
      flag = described_class.new("4.0.0.dev")
      expect(flag.bundler_4_mode?).to eq(true)
      expect(flag.bundler_5_mode?).to eq(false)
    end

    it "handles single-segment version strings" do
      flag = described_class.new("2")
      expect(flag.bundler_2_mode?).to eq(true)
      expect(flag.bundler_3_mode?).to eq(false)
    end
  end

  describe "bundler_N_mode? methods" do
    context "with bundler version 1.0.0" do
      let(:flag) { described_class.new("1.0.0") }

      it "returns true for bundler_1_mode?" do
        expect(flag.bundler_1_mode?).to eq(true)
      end

      it "returns false for bundler_2_mode? through bundler_10_mode?" do
        (2..10).each do |v|
          expect(flag.send(:"bundler_#{v}_mode?")).to eq(false)
        end
      end
    end

    context "with bundler version 2.5.0" do
      let(:flag) { described_class.new("2.5.0") }

      it "returns true for bundler_1_mode? and bundler_2_mode?" do
        expect(flag.bundler_1_mode?).to eq(true)
        expect(flag.bundler_2_mode?).to eq(true)
      end

      it "returns false for bundler_3_mode? and higher" do
        (3..10).each do |v|
          expect(flag.send(:"bundler_#{v}_mode?")).to eq(false)
        end
      end
    end

    context "with bundler version 3.0.0" do
      let(:flag) { described_class.new("3.0.0") }

      it "returns true for bundler_1_mode? through bundler_3_mode?" do
        expect(flag.bundler_1_mode?).to eq(true)
        expect(flag.bundler_2_mode?).to eq(true)
        expect(flag.bundler_3_mode?).to eq(true)
      end

      it "returns false for bundler_4_mode? and higher" do
        (4..10).each do |v|
          expect(flag.send(:"bundler_#{v}_mode?")).to eq(false)
        end
      end
    end

    context "with bundler version 4.0.0" do
      let(:flag) { described_class.new("4.0.0") }

      it "returns true for bundler_1_mode? through bundler_4_mode?" do
        (1..4).each do |v|
          expect(flag.send(:"bundler_#{v}_mode?")).to eq(true)
        end
      end

      it "returns false for bundler_5_mode? and higher" do
        (5..10).each do |v|
          expect(flag.send(:"bundler_#{v}_mode?")).to eq(false)
        end
      end
    end

    context "with bundler version 10.0.0" do
      let(:flag) { described_class.new("10.0.0") }

      it "returns true for all bundler_N_mode? methods from 1 to 10" do
        (1..10).each do |v|
          expect(flag.send(:"bundler_#{v}_mode?")).to eq(true)
        end
      end
    end

    it "responds to all bundler_N_mode? methods from 1 to 10" do
      flag = described_class.new("1.0.0")
      (1..10).each do |v|
        expect(flag).to respond_to(:"bundler_#{v}_mode?")
      end
    end
  end

  describe "#removed_major?" do
    context "with bundler version 3.0.0 (major version 3)" do
      let(:flag) { described_class.new("3.0.0") }

      it "returns true when target major version is less than current major" do
        expect(flag.removed_major?(1)).to eq(true)
        expect(flag.removed_major?(2)).to eq(true)
      end

      it "returns false when target major version equals current major" do
        expect(flag.removed_major?(3)).to eq(false)
      end

      it "returns false when target major version is greater than current major" do
        expect(flag.removed_major?(4)).to eq(false)
        expect(flag.removed_major?(5)).to eq(false)
      end
    end

    context "with bundler version 1.0.0 (major version 1)" do
      let(:flag) { described_class.new("1.0.0") }

      it "returns false for target 1 (equal)" do
        expect(flag.removed_major?(1)).to eq(false)
      end

      it "returns false for target 2 (greater)" do
        expect(flag.removed_major?(2)).to eq(false)
      end
    end

    context "with bundler version 5.0.0 (major version 5)" do
      let(:flag) { described_class.new("5.0.0") }

      it "returns true for all targets below 5" do
        (1..4).each do |target|
          expect(flag.removed_major?(target)).to eq(true)
        end
      end

      it "returns false for target 5 and above" do
        expect(flag.removed_major?(5)).to eq(false)
        expect(flag.removed_major?(6)).to eq(false)
      end
    end
  end

  describe "#deprecated_major?" do
    context "with bundler version 3.0.0 (major version 3)" do
      let(:flag) { described_class.new("3.0.0") }

      it "returns true when target major version is less than current major" do
        expect(flag.deprecated_major?(1)).to eq(true)
        expect(flag.deprecated_major?(2)).to eq(true)
      end

      it "returns true when target major version equals current major" do
        expect(flag.deprecated_major?(3)).to eq(true)
      end

      it "returns false when target major version is greater than current major" do
        expect(flag.deprecated_major?(4)).to eq(false)
        expect(flag.deprecated_major?(5)).to eq(false)
      end
    end

    context "with bundler version 1.0.0 (major version 1)" do
      let(:flag) { described_class.new("1.0.0") }

      it "returns true for target 1 (equal)" do
        expect(flag.deprecated_major?(1)).to eq(true)
      end

      it "returns false for target 2 (greater)" do
        expect(flag.deprecated_major?(2)).to eq(false)
      end
    end

    context "with bundler version 5.0.0 (major version 5)" do
      let(:flag) { described_class.new("5.0.0") }

      it "returns true for all targets up to and including 5" do
        (1..5).each do |target|
          expect(flag.deprecated_major?(target)).to eq(true)
        end
      end

      it "returns false for targets above 5" do
        expect(flag.deprecated_major?(6)).to eq(false)
        expect(flag.deprecated_major?(7)).to eq(false)
      end
    end
  end

  describe "removed_major? vs deprecated_major? boundary distinction" do
    let(:flag) { described_class.new("3.0.0") }

    it "deprecated_major? is true at boundary but removed_major? is false" do
      expect(flag.deprecated_major?(3)).to eq(true)
      expect(flag.removed_major?(3)).to eq(false)
    end

    it "both are true when target is below current major" do
      expect(flag.deprecated_major?(2)).to eq(true)
      expect(flag.removed_major?(2)).to eq(true)
    end

    it "both are false when target is above current major" do
      expect(flag.deprecated_major?(4)).to eq(false)
      expect(flag.removed_major?(4)).to eq(false)
    end
  end
end
