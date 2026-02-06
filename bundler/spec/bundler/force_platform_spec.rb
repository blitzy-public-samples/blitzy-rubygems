# frozen_string_literal: true

require "spec_helper"
require "bundler/force_platform"

RSpec.describe Bundler::ForcePlatform do
  # Test class that includes ForcePlatform and provides a name accessor,
  # mirroring how LazySpecification and Gem::Dependency include it in production.
  let(:test_class) do
    Class.new do
      include Bundler::ForcePlatform

      attr_accessor :name

      def initialize(name)
        @name = name
      end
    end
  end

  describe "#default_force_ruby_platform" do
    context "on non-TruffleRuby engines" do
      it "returns false regardless of gem name" do
        instance = test_class.new("rails")
        result = instance.default_force_ruby_platform
        expect(result).to eq(false)
        expect(result).to be_a(FalseClass)
      end

      it "returns false for any gem name" do
        instance_a = test_class.new("nokogiri")
        instance_b = test_class.new("ffi")
        expect(instance_a.default_force_ruby_platform).to eq(false)
        expect(instance_b.default_force_ruby_platform).to eq(false)
      end

      it "returns false for empty gem name" do
        instance = test_class.new("")
        expect(instance.default_force_ruby_platform).to eq(false)
        expect(instance.default_force_ruby_platform).to be_falsey
      end
    end

    context "on TruffleRuby engine" do
      before do
        stub_const("RUBY_ENGINE", "truffleruby")
        # Define the constant that is only present on TruffleRuby at runtime
        stub_const("Gem::Platform::REUSE_AS_BINARY_ON_TRUFFLERUBY", %w[ffi sassc grpc].freeze)
      end

      it "returns false for gems in the REUSE_AS_BINARY_ON_TRUFFLERUBY allowlist" do
        instance = test_class.new("ffi")
        result = instance.default_force_ruby_platform
        expect(result).to eq(false)
        expect(result).to be_falsey
      end

      it "returns true for gems not in the allowlist" do
        instance = test_class.new("rails")
        result = instance.default_force_ruby_platform
        expect(result).to eq(true)
        expect(result).to be_truthy
      end

      it "returns true for an unknown gem name not in the allowlist" do
        instance = test_class.new("my-custom-gem")
        expect(instance.default_force_ruby_platform).to eq(true)
        expect(instance.name).to eq("my-custom-gem")
      end

      it "returns false for each allowlisted gem" do
        %w[ffi sassc grpc].each do |gem_name|
          instance = test_class.new(gem_name)
          expect(instance.default_force_ruby_platform).to eq(false)
        end
      end
    end
  end

  describe "module inclusion" do
    it "can be included in any class with a name method" do
      instance = test_class.new("test-gem")
      expect(instance).to respond_to(:default_force_ruby_platform)
      expect(instance).to respond_to(:name)
    end

    it "is a Module" do
      expect(Bundler::ForcePlatform).to be_a(Module)
      expect(test_class.ancestors).to include(Bundler::ForcePlatform)
    end

    it "is included in the test class ancestor chain" do
      expect(test_class.include?(Bundler::ForcePlatform)).to eq(true)
      expect(test_class.new("gem").default_force_ruby_platform).to eq(false)
    end
  end
end
