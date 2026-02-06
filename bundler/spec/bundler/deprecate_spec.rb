# frozen_string_literal: true

RSpec.describe Bundler::Deprecate do
  # Ensure skip state is clean before and after each test
  # to prevent cross-test contamination
  around :each do |example|
    original_skip = described_class.skip
    described_class.skip = false
    example.run
  ensure
    described_class.skip = original_skip
  end

  describe ".skip" do
    it "returns false by default" do
      expect(described_class.skip).to eq(false)
    end

    it "responds to the skip class method" do
      expect(described_class).to respond_to(:skip)
    end

    it "returns the current skip flag value" do
      described_class.skip = true
      expect(described_class.skip).to eq(true)
    end
  end

  describe ".skip=" do
    it "responds to the skip= class method" do
      expect(described_class).to respond_to(:skip=)
    end

    it "sets the skip flag to true" do
      described_class.skip = true
      expect(described_class.skip).to eq(true)
    end

    it "sets the skip flag to false" do
      described_class.skip = true
      described_class.skip = false
      expect(described_class.skip).to eq(false)
    end

    it "accepts truthy values" do
      described_class.skip = "yes"
      expect(described_class.skip).to be_truthy
    end

    it "accepts nil as a falsey value" do
      described_class.skip = nil
      expect(described_class.skip).to be_falsey
    end
  end

  describe ".skip_during" do
    it "responds to the skip_during class method" do
      expect(described_class).to respond_to(:skip_during)
    end

    it "sets skip to true inside the block" do
      observed_skip = nil
      described_class.skip_during do
        observed_skip = described_class.skip
      end
      expect(observed_skip).to eq(true)
    end

    it "restores skip to false after the block when originally false" do
      described_class.skip = false
      described_class.skip_during do
        # inside block, skip is true
      end
      expect(described_class.skip).to eq(false)
    end

    it "restores skip to true after the block when originally true" do
      described_class.skip = true
      described_class.skip_during do
        # inside block, skip is true
      end
      expect(described_class.skip).to eq(true)
    end

    it "returns the value of the block" do
      result = described_class.skip_during { 42 }
      expect(result).to eq(42)
    end

    it "returns the block value for string results" do
      result = described_class.skip_during { "hello" }
      expect(result).to eq("hello")
    end

    it "returns nil when block returns nil" do
      result = described_class.skip_during { nil }
      expect(result).to be_nil
    end

    it "restores skip to false even when block raises an exception" do
      described_class.skip = false
      begin
        described_class.skip_during do
          raise RuntimeError, "test error"
        end
      rescue RuntimeError
        # expected
      end
      expect(described_class.skip).to eq(false)
    end

    it "restores skip to true even when block raises an exception" do
      described_class.skip = true
      begin
        described_class.skip_during do
          raise RuntimeError, "test error"
        end
      rescue RuntimeError
        # expected
      end
      expect(described_class.skip).to eq(true)
    end

    it "propagates exceptions raised inside the block" do
      expect do
        described_class.skip_during do
          raise ArgumentError, "bad argument"
        end
      end.to raise_error(ArgumentError, "bad argument")
    end

    it "allows nested skip_during calls" do
      outer_during = nil
      inner_during = nil

      described_class.skip_during do
        outer_during = described_class.skip
        described_class.skip_during do
          inner_during = described_class.skip
        end
      end

      expect(outer_during).to eq(true)
      expect(inner_during).to eq(true)
      expect(described_class.skip).to eq(false)
    end
  end

  describe "module identity" do
    it "is defined as a constant under Bundler" do
      expect(defined?(Bundler::Deprecate)).to eq("constant")
    end

    it "is the same object as Gem::Deprecate when Gem::Deprecate exists" do
      if defined?(Gem::Deprecate)
        expect(described_class).to eq(Gem::Deprecate)
      end
    end
  end

  describe "deprecation warning integration" do
    # Use a fresh anonymous class for each test to avoid polluting
    # global state with deprecated method definitions
    let(:test_class) do
      klass = Class.new do
        def old_method
          "old result"
        end

        extend Bundler::Deprecate
        deprecate :old_method, "new_method", 2099, 1
      end
      klass
    end

    it "suppresses deprecation warnings when skip is true" do
      described_class.skip = true
      instance = test_class.new
      expect { instance.old_method }.not_to output.to_stderr
    end

    it "emits deprecation warnings when skip is false" do
      described_class.skip = false
      instance = test_class.new
      expect { instance.old_method }.to output(/deprecated/).to_stderr
    end

    it "suppresses warnings inside skip_during block" do
      described_class.skip = false
      instance = test_class.new
      described_class.skip_during do
        expect { instance.old_method }.not_to output.to_stderr
      end
    end

    it "preserves the return value of the deprecated method" do
      described_class.skip = true
      instance = test_class.new
      expect(instance.old_method).to eq("old result")
    end
  end

  describe "skip state transitions" do
    it "transitions from false to true to false correctly" do
      expect(described_class.skip).to eq(false)
      described_class.skip = true
      expect(described_class.skip).to eq(true)
      described_class.skip = false
      expect(described_class.skip).to eq(false)
    end

    it "handles rapid toggling without state corruption" do
      10.times do
        described_class.skip = true
        expect(described_class.skip).to eq(true)
        described_class.skip = false
        expect(described_class.skip).to eq(false)
      end
    end

    it "skip_during does not affect skip flag when called multiple times" do
      described_class.skip = false
      3.times do
        described_class.skip_during { "work" }
        expect(described_class.skip).to eq(false)
      end
    end
  end
end
