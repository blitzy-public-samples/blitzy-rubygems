# frozen_string_literal: true

require "spec_helper"
require "bundler/force_platform"

RSpec.describe Bundler::ForcePlatform do
  # A lightweight test class that includes the ForcePlatform module and provides
  # a name accessor, mirroring how production classes such as LazySpecification
  # and Dependency include the module with a name attribute.
  let(:test_class) do
    Class.new do
      include Bundler::ForcePlatform

      attr_accessor :name

      def initialize(name)
        @name = name
      end
    end
  end

  subject { test_class.new("rails") }

  describe "#default_force_ruby_platform" do
    context "flag behavior on standard Ruby engine" do
      it "returns false for a typical gem name" do
        result = subject.default_force_ruby_platform
        expect(result).to eq(false)
        expect(result).to be(false)
      end

      it "returns a boolean false, not nil or another falsey value" do
        instance = test_class.new("nokogiri")
        result = instance.default_force_ruby_platform
        expect(result).to be_a(FalseClass)
        expect(result).to eq(false)
      end

      it "returns false regardless of gem name" do
        %w[rails nokogiri ffi sassc my-custom-gem].each do |gem_name|
          instance = test_class.new(gem_name)
          expect(instance.default_force_ruby_platform).to eq(false)
        end
        expect(test_class.new("another-gem").default_force_ruby_platform).to be(false)
      end

      it "returns false for an empty gem name" do
        instance = test_class.new("")
        expect(instance.default_force_ruby_platform).to eq(false)
        expect(instance.default_force_ruby_platform).to be_falsey
      end

      it "is available as an instance method via module inclusion" do
        expect(subject).to respond_to(:default_force_ruby_platform)
        expect(subject.default_force_ruby_platform).to eq(false)
      end
    end

    context "platform override via module inclusion" do
      it "can be included in any class that provides a name method" do
        custom_class = Class.new do
          include Bundler::ForcePlatform

          def name
            "custom-gem"
          end
        end
        instance = custom_class.new
        expect(instance).to respond_to(:default_force_ruby_platform)
        expect(instance.default_force_ruby_platform).to eq(false)
      end

      it "provides both default_force_ruby_platform and name on the including class" do
        instance = test_class.new("test-gem")
        expect(instance).to respond_to(:default_force_ruby_platform)
        expect(instance).to respond_to(:name)
      end

      it "is a Module and appears in the ancestor chain of including classes" do
        expect(described_class).to be_a(Module)
        expect(test_class.ancestors).to include(described_class)
      end

      it "is reported as included by the test class" do
        expect(test_class.include?(described_class)).to eq(true)
        expect(test_class.new("gem").default_force_ruby_platform).to eq(false)
      end
    end

    context "TruffleRuby behavior" do
      before do
        stub_const("RUBY_ENGINE", "truffleruby")
        stub_const("Gem::Platform::REUSE_AS_BINARY_ON_TRUFFLERUBY", %w[ffi sassc grpc].freeze)
      end

      it "returns true for gems not in the REUSE_AS_BINARY_ON_TRUFFLERUBY allowlist" do
        instance = test_class.new("rails")
        result = instance.default_force_ruby_platform
        expect(result).to eq(true)
        expect(result).to be(true)
      end

      it "returns false for gems present in the REUSE_AS_BINARY_ON_TRUFFLERUBY allowlist" do
        instance = test_class.new("ffi")
        result = instance.default_force_ruby_platform
        expect(result).to eq(false)
        expect(result).to be_falsey
      end

      it "returns false for every allowlisted gem name" do
        %w[ffi sassc grpc].each do |allowlisted_name|
          instance = test_class.new(allowlisted_name)
          expect(instance.default_force_ruby_platform).to eq(false)
        end
        expect(test_class.new("ffi").default_force_ruby_platform).to be(false)
      end

      it "returns true for an unknown custom gem name not in the allowlist" do
        instance = test_class.new("my-custom-gem")
        expect(instance.default_force_ruby_platform).to eq(true)
        expect(instance.name).to eq("my-custom-gem")
      end

      it "consults the name method from the including class during evaluation" do
        instance = test_class.new("rails")
        allow(instance).to receive(:name).and_call_original
        result = instance.default_force_ruby_platform
        expect(result).to eq(true)
        expect(instance).to have_received(:name)
      end

      it "returns true for an empty gem name since it is not in the allowlist" do
        instance = test_class.new("")
        expect(instance.default_force_ruby_platform).to eq(true)
        expect(instance.default_force_ruby_platform).to be_truthy
      end
    end
  end
end
