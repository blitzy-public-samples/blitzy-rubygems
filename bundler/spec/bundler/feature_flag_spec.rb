# frozen_string_literal: true

require "spec_helper"
require "bundler/feature_flag"

RSpec.describe Bundler::FeatureFlag do
  subject(:flag) { described_class.new(version) }

  describe "#initialize" do
    let(:version) { "2.5.0" }

    it "creates a FeatureFlag instance from a version string" do
      expect(subject).to be_a(Bundler::FeatureFlag)
      expect(subject.bundler_2_mode?).to be true
    end

    context "with a pre-release version string" do
      let(:version) { "4.0.0.dev" }

      it "extracts the correct major version from pre-release versions" do
        expect(flag.bundler_4_mode?).to be_truthy
        expect(flag.bundler_5_mode?).to be_falsey
      end
    end

    context "with a single-segment version string" do
      let(:version) { "3" }

      it "correctly interprets single-segment versions" do
        expect(flag.bundler_3_mode?).to eq(true)
        expect(flag.bundler_4_mode?).to eq(false)
      end
    end
  end

  describe "#bundler_N_mode?" do
    context "with version 1.0.0 (default values)" do
      let(:version) { "1.0.0" }

      before do
        flag
      end

      it "returns true only for bundler_1_mode?" do
        expect(flag.bundler_1_mode?).to be_truthy
        expect(flag.bundler_2_mode?).to be_falsey
      end

      it "returns false for all bundler_N_mode? where N > 1" do
        (2..10).each do |v|
          expect(flag.send(:"bundler_#{v}_mode?")).to eq(false)
        end
      end
    end

    context "with version 2.5.0" do
      let(:version) { "2.5.0" }

      it "returns true for bundler_1_mode? and bundler_2_mode?" do
        expect(flag.bundler_1_mode?).to be true
        expect(flag.bundler_2_mode?).to be true
      end

      it "returns false for bundler_3_mode? and higher" do
        expect(flag.bundler_3_mode?).to be false
        expect(flag.bundler_4_mode?).to be false
      end
    end

    context "with version 3.0.0" do
      let(:version) { "3.0.0" }

      it "returns true for modes up to and including 3" do
        expect(flag.bundler_1_mode?).to eq(true)
        expect(flag.bundler_2_mode?).to eq(true)
        expect(flag.bundler_3_mode?).to eq(true)
      end

      it "returns false for bundler_4_mode? and above" do
        expect(flag.bundler_4_mode?).to be_falsey
        expect(flag.bundler_10_mode?).to be_falsey
      end
    end

    context "with version 10.0.0" do
      let(:version) { "10.0.0" }

      it "returns true for all bundler_N_mode? methods from 1 to 10" do
        (1..10).each do |v|
          expect(flag.send(:"bundler_#{v}_mode?")).to eq(true)
        end
      end
    end
  end

  describe "flag registration" do
    let(:version) { "1.0.0" }

    it "responds to all bundler_N_mode? methods from 1 to 10" do
      (1..10).each do |v|
        expect(flag).to respond_to(:"bundler_#{v}_mode?")
      end
    end

    it "responds to removed_major? and deprecated_major?" do
      expect(flag).to respond_to(:removed_major?)
      expect(flag).to respond_to(:deprecated_major?)
    end
  end

  describe "#removed_major?" do
    context "with version 3.0.0 (major version 3)" do
      let(:version) { "3.0.0" }

      it "returns true when target major version is less than current major" do
        expect(flag.removed_major?(1)).to eq(true)
        expect(flag.removed_major?(2)).to eq(true)
      end

      it "returns false when target major version equals or exceeds current major" do
        expect(flag.removed_major?(3)).to be false
        expect(flag.removed_major?(4)).to be_falsey
      end
    end

    context "with version 2.0.0 (major version 2)" do
      let(:version) { "2.0.0" }

      it "returns true only for targets below current major" do
        expect(flag.removed_major?(1)).to be_truthy
        expect(flag.removed_major?(2)).to be_falsey
      end
    end

    context "with version 5.0.0 (major version 5)" do
      let(:version) { "5.0.0" }

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
    context "with version 2.0.0 (major version 2)" do
      let(:version) { "2.0.0" }

      it "returns true when target major version is at or below current major" do
        expect(flag.deprecated_major?(2)).to eq(true)
        expect(flag.deprecated_major?(1)).to eq(true)
      end

      it "returns false when target major version exceeds current major" do
        expect(flag.deprecated_major?(3)).to be_falsey
        expect(flag.deprecated_major?(4)).to be_falsey
      end
    end

    context "with version 1.0.0 (major version 1)" do
      let(:version) { "1.0.0" }

      it "returns true for target 1 (equal) and false for target 2 (greater)" do
        expect(flag.deprecated_major?(1)).to be_truthy
        expect(flag.deprecated_major?(2)).to be_falsey
      end
    end

    context "with version 5.0.0 (major version 5)" do
      let(:version) { "5.0.0" }

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
    let(:version) { "3.0.0" }

    it "deprecated_major? is true at boundary but removed_major? is false" do
      expect(flag.deprecated_major?(3)).to be true
      expect(flag.removed_major?(3)).to be false
    end

    it "both return true when target is below current major" do
      expect(flag.deprecated_major?(2)).to be_truthy
      expect(flag.removed_major?(2)).to be_truthy
    end

    it "both return false when target is above current major" do
      expect(flag.deprecated_major?(4)).to be_falsey
      expect(flag.removed_major?(4)).to be_falsey
    end
  end
end
