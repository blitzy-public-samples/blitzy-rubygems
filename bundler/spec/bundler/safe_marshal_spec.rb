# frozen_string_literal: true

require "spec_helper"
require "bundler/safe_marshal"

RSpec.describe Bundler::SafeMarshal do
  subject { described_class }

  describe "ALLOWED_CLASSES" do
    let(:allowed_classes) { described_class::ALLOWED_CLASSES }

    it "is frozen and immutable" do
      expect(allowed_classes).to be_frozen
      expect(allowed_classes).to be_a(Array)
    end

    it "contains exactly the nine expected allowed classes" do
      expected = [Array, FalseClass, Gem::Specification, Gem::Version, Hash, String, Symbol, Time, TrueClass]
      expect(allowed_classes).to include(*expected)
      expect(allowed_classes.size).to eq(9)
    end
  end

  describe "ERROR" do
    let(:error_template) { described_class::ERROR }

    it "is a format string referencing the unexpected class and allowed list" do
      expect(error_template).to be_a(String)
      expect(error_template).to match(/Unexpected class/)
    end

    it "contains format placeholders for class name and allowed classes" do
      expect(error_template).to include("%s")
      expect(error_template).to match(/Only .+ are allowed/)
    end
  end

  describe ".proc" do
    subject(:safe_proc) { described_class.proc }

    it "returns a Proc identical to the PROC constant" do
      expect(safe_proc).to be_a(Proc)
      expect(safe_proc).to eq(described_class::PROC)
    end

    context "with allowed class instances" do
      it "passes through String instances unchanged" do
        result = safe_proc.call("hello world")
        expect(result).to eq("hello world")
        expect(result).to be_a(String)
      end

      it "passes through Array instances unchanged" do
        arr = ["a", "b", "c"]
        result = safe_proc.call(arr)
        expect(result).to eq(arr)
        expect(result).to be_a(Array)
      end

      it "passes through Hash instances unchanged" do
        hash = { "key" => "value" }
        result = safe_proc.call(hash)
        expect(result).to eq(hash)
        expect(result).to be_a(Hash)
      end

      it "passes through Symbol and boolean instances" do
        expect(safe_proc.call(:sym)).to eq(:sym)
        expect(safe_proc.call(true)).to eq(true)
        expect(safe_proc.call(false)).to eq(false)
      end

      it "passes through Time instances unchanged" do
        now = Time.now
        result = safe_proc.call(now)
        expect(result).to eq(now)
        expect(result).to be_a(Time)
      end
    end

    context "with disallowed class instances" do
      it "raises TypeError for Integer" do
        expect { safe_proc.call(42) }.to raise_error(TypeError)
        expect { safe_proc.call(42) }.to raise_error(TypeError, match(/Integer/))
      end

      it "raises TypeError for Float" do
        expect { safe_proc.call(3.14) }.to raise_error(TypeError)
        expect { safe_proc.call(3.14) }.to raise_error(TypeError, match(/Float/))
      end

      it "includes the disallowed class name and allowed classes in the error" do
        expect { safe_proc.call(42) }.to raise_error(TypeError, /Only .+ are allowed/)
        expect { safe_proc.call(Object.new) }.to raise_error(TypeError, match(/Object/))
      end
    end
  end

  context "safe loading with Marshal" do
    let(:safe_proc) { described_class.proc }

    it "loads marshaled String data preserving value and type" do
      original = "test string"
      data = Marshal.dump(original)
      result = Marshal.load(data, safe_proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result).to be_a(String)
    end

    it "loads marshaled Array of allowed types preserving structure" do
      original = ["one", "two", "three"]
      data = Marshal.dump(original)
      result = Marshal.load(data, safe_proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result).to be_a(Array)
    end

    it "loads marshaled Hash with nested Array values" do
      original = { "key" => "value", "list" => ["a", "b"] }
      data = Marshal.dump(original)
      result = Marshal.load(data, safe_proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result).to be_a(Hash)
    end

    it "loads marshaled booleans and Symbols individually" do
      [true, false, :test_sym].each do |original|
        data = Marshal.dump(original)
        result = Marshal.load(data, safe_proc) # rubocop:disable Security/MarshalLoad
        expect(result).to eq(original)
      end
    end
  end

  context "class restriction enforcement" do
    let(:safe_proc) { described_class.proc }
    let(:regexp_data) { Marshal.dump(/pattern/) }

    before do
      @range_data = Marshal.dump(1..10)
    end

    it "raises TypeError when marshaled data contains Regexp" do
      expect { Marshal.load(regexp_data, safe_proc) }.to raise_error(TypeError) # rubocop:disable Security/MarshalLoad
      expect { Marshal.load(regexp_data, safe_proc) }.to raise_error(TypeError, match(/Regexp/)) # rubocop:disable Security/MarshalLoad
    end

    it "raises TypeError for marshaled Range due to internal Integer components" do
      expect { Marshal.load(@range_data, safe_proc) }.to raise_error(TypeError) # rubocop:disable Security/MarshalLoad
      expect { Marshal.load(@range_data, safe_proc) }.to raise_error(TypeError, /Integer/) # rubocop:disable Security/MarshalLoad
    end

    it "includes class name and allowed classes list in the TypeError message" do
      expect { Marshal.load(regexp_data, safe_proc) }.to raise_error(TypeError, /Regexp/) # rubocop:disable Security/MarshalLoad
      expect { Marshal.load(regexp_data, safe_proc) }.to raise_error(TypeError, /Only .+ are allowed/) # rubocop:disable Security/MarshalLoad
    end
  end

  context "round-trip output validation" do
    let(:safe_proc) { described_class.proc }

    it "preserves simple hash key-value pairs through dump and load" do
      original = { "name" => "test-gem", "version" => "1.0.0" }
      data = Marshal.dump(original)
      result = Marshal.load(data, safe_proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result["name"]).to eq("test-gem")
    end

    it "preserves nested structures with mixed allowed types" do
      original = {
        "gems" => ["bundler", "rake"],
        "active" => true,
        "label" => :production,
      }
      data = Marshal.dump(original)
      result = Marshal.load(data, safe_proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result["gems"]).to eq(["bundler", "rake"])
    end

    it "preserves Gem::Version identity through marshal round-trip" do
      original = Gem::Version.new("3.2.1")
      data = Marshal.dump(original)
      result = Marshal.load(data, safe_proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result).to be_a(Gem::Version)
    end

    it "rejects marshaled Time due to internal Integer representation" do
      data = Marshal.dump(Time.now)
      expect { Marshal.load(data, safe_proc) }.to raise_error(TypeError) # rubocop:disable Security/MarshalLoad
      expect { Marshal.load(data, safe_proc) }.to raise_error(TypeError, /Integer/) # rubocop:disable Security/MarshalLoad
    end
  end
end
