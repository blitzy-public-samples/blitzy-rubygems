# frozen_string_literal: true

require "spec_helper"
require "bundler/deprecate"

RSpec.describe Bundler::Deprecate do
  subject(:deprecate_module) { described_class }

  # Ensure skip state is clean before and after each example
  # to prevent cross-test contamination of the global skip flag
  around :each do |example|
    original_skip = described_class.skip
    described_class.skip = false
    example.run
  ensure
    described_class.skip = original_skip
  end

  describe "module identity" do
    it "is defined as a constant under Bundler and responds to all expected class methods" do
      expect(defined?(Bundler::Deprecate)).to eq("constant")
      expect(deprecate_module).to respond_to(:skip)
      expect(deprecate_module).to respond_to(:skip=)
      expect(deprecate_module).to respond_to(:skip_during)
    end

    it "is aliased from Gem::Deprecate and shares identity" do
      expect(described_class).to eq(Gem::Deprecate)
      expect(described_class).to be(Gem::Deprecate)
    end
  end

  describe ".skip" do
    it "returns false by default and is falsey" do
      expect(described_class.skip).to eq(false)
      expect(described_class.skip).to be_falsey
    end

    it "reflects the value previously set via skip= and is truthy when true" do
      described_class.skip = true
      expect(described_class.skip).to eq(true)
      expect(described_class.skip).to be_truthy
    end
  end

  describe ".skip=" do
    it "sets the skip flag to true and the value persists" do
      described_class.skip = true
      expect(described_class.skip).to eq(true)
      expect(described_class.skip).to be(true)
    end

    it "sets the skip flag back to false after it was true" do
      described_class.skip = true
      described_class.skip = false
      expect(described_class.skip).to eq(false)
      expect(described_class.skip).to be_falsey
    end

    it "accepts truthy and falsey non-boolean values" do
      described_class.skip = "yes"
      expect(described_class.skip).to be_truthy
      described_class.skip = nil
      expect(described_class.skip).to be_falsey
    end
  end

  describe ".skip_during" do
    it "sets skip to true inside the block and restores to false after" do
      observed_skip = nil
      described_class.skip_during do
        observed_skip = described_class.skip
      end
      expect(observed_skip).to eq(true)
      expect(described_class.skip).to eq(false)
    end

    it "restores skip to false after block when originally false and returns block value" do
      described_class.skip = false
      result = described_class.skip_during { "work" }
      expect(described_class.skip).to eq(false)
      expect(result).to eq("work")
    end

    it "restores skip to true after block when originally true and returns block value" do
      described_class.skip = true
      result = described_class.skip_during { "done" }
      expect(described_class.skip).to eq(true)
      expect(result).to eq("done")
    end

    it "returns the block return value for various types" do
      expect(described_class.skip_during { 42 }).to eq(42)
      expect(described_class.skip_during { "hello" }).to eq("hello")
    end

    it "handles nested skip_during calls and restores to the original value" do
      outer_skip = nil
      inner_skip = nil
      described_class.skip_during do
        outer_skip = described_class.skip
        described_class.skip_during do
          inner_skip = described_class.skip
        end
      end
      expect(outer_skip).to eq(true)
      expect(inner_skip).to eq(true)
      expect(described_class.skip).to eq(false)
    end

    context "skip flag behavior on exceptions" do
      it "restores skip to false when block raises and propagates the error" do
        described_class.skip = false
        expect do
          described_class.skip_during { raise RuntimeError, "test error" }
        end.to raise_error(RuntimeError, "test error")
        expect(described_class.skip).to eq(false)
      end

      it "restores skip to true when block raises and propagates the error" do
        described_class.skip = true
        expect do
          described_class.skip_during { raise ArgumentError, "bad argument" }
        end.to raise_error(ArgumentError, "bad argument")
        expect(described_class.skip).to eq(true)
      end

      it "does not corrupt skip state after multiple sequential calls" do
        described_class.skip = false
        3.times { described_class.skip_during { "work" } }
        expect(described_class.skip).to eq(false)
        expect(described_class.skip).to be_falsey
      end
    end
  end

  context "warning emission" do
    let(:test_class) do
      Class.new do
        def old_method
          "old result"
        end

        extend Bundler::Deprecate
        deprecate :old_method, "new_method", 2099, 1
      end
    end

    before do
      described_class.skip = false
    end

    after do
      described_class.skip = false
    end

    it "emits deprecation warnings to stderr when skip is false" do
      instance = test_class.new
      allow($stderr).to receive(:write).and_call_original
      expect { instance.old_method }.to output(/deprecated/).to_stderr
      expect { instance.old_method }.to output(/new_method/).to_stderr
    end

    it "suppresses deprecation warnings when skip is true" do
      described_class.skip = true
      instance = test_class.new
      expect { instance.old_method }.not_to output.to_stderr
      expect(instance.old_method).to eq("old result")
    end

    it "suppresses warnings inside skip_during block and resumes after" do
      instance = test_class.new
      described_class.skip_during do
        expect { instance.old_method }.not_to output.to_stderr
      end
      expect { instance.old_method }.to output(/deprecated/).to_stderr
    end

    it "preserves the return value of the deprecated method regardless of skip" do
      described_class.skip = true
      instance = test_class.new
      expect(instance.old_method).to eq("old result")
      expect(instance.old_method).to be_truthy
    end
  end

  context "replacement indication" do
    let(:test_class_with_replacement) do
      Class.new do
        def legacy_method
          "legacy"
        end

        extend Bundler::Deprecate
        deprecate :legacy_method, "modern_method", 2099, 6
      end
    end

    let(:test_class_no_replacement) do
      Class.new do
        def obsolete_method
          "obsolete"
        end

        extend Bundler::Deprecate
        deprecate :obsolete_method, :none, 2099, 6
      end
    end

    before do
      described_class.skip = false
    end

    after do
      described_class.skip = false
    end

    it "references the replacement method name in the warning message" do
      instance = test_class_with_replacement.new
      allow($stderr).to receive(:write).and_call_original
      expect { instance.legacy_method }.to output(/use modern_method instead/).to_stderr
      expect { instance.legacy_method }.to output(/deprecated/).to_stderr
    end

    it "indicates no replacement when :none is specified" do
      instance = test_class_no_replacement.new
      expect { instance.obsolete_method }.to output(/no replacement/).to_stderr
      expect { instance.obsolete_method }.to output(/deprecated/).to_stderr
    end

    it "includes the target date in the deprecation message" do
      instance = test_class_with_replacement.new
      expect { instance.legacy_method }.to output(/2099/).to_stderr
      expect { instance.legacy_method }.to output(/06/).to_stderr
    end

    it "preserves return values of deprecated methods regardless of replacement type" do
      described_class.skip = true
      expect(test_class_with_replacement.new.legacy_method).to eq("legacy")
      expect(test_class_no_replacement.new.obsolete_method).to eq("obsolete")
    end
  end

  describe "skip state transitions" do
    it "transitions from false to true to false in sequence" do
      expect(described_class.skip).to eq(false)
      described_class.skip = true
      expect(described_class.skip).to eq(true)
      described_class.skip = false
      expect(described_class.skip).to eq(false)
    end

    it "handles rapid toggling without state corruption" do
      10.times do
        described_class.skip = true
        expect(described_class.skip).to be(true)
        described_class.skip = false
        expect(described_class.skip).to be(false)
      end
    end
  end
end
