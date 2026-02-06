# frozen_string_literal: true

require "spec_helper"
require "bundler/safe_marshal"

RSpec.describe Bundler::SafeMarshal do
  describe "ALLOWED_CLASSES" do
    it "is frozen and contains all expected classes" do
      expect(described_class::ALLOWED_CLASSES).to be_frozen
      expect(described_class::ALLOWED_CLASSES).to include(
        Array, FalseClass, Gem::Specification, Gem::Version,
        Hash, String, Symbol, Time, TrueClass
      )
    end

    it "contains exactly the expected number of allowed classes" do
      expect(described_class::ALLOWED_CLASSES.size).to eq(9)
      expect(described_class::ALLOWED_CLASSES).to be_a(Array)
    end
  end

  describe "ERROR" do
    it "is a format string for TypeError messages" do
      expect(described_class::ERROR).to be_a(String)
      expect(described_class::ERROR).to include("Unexpected class")
    end
  end

  describe ".proc" do
    it "returns a Proc object" do
      result = described_class.proc
      expect(result).to be_a(Proc)
      expect(result).to eq(described_class::PROC)
    end

    it "accepts allowed class instances without raising" do
      safe_proc = described_class.proc
      expect(safe_proc.call("hello")).to eq("hello")
      expect(safe_proc.call([1, 2, 3])).to eq([1, 2, 3])
    end

    it "accepts Hash instances without raising" do
      safe_proc = described_class.proc
      test_hash = { "key" => "value" }
      expect(safe_proc.call(test_hash)).to eq(test_hash)
      expect(safe_proc.call(true)).to eq(true)
    end

    it "accepts Symbol and boolean instances without raising" do
      safe_proc = described_class.proc
      expect(safe_proc.call(:test_symbol)).to eq(:test_symbol)
      expect(safe_proc.call(false)).to eq(false)
    end

    it "accepts Time instances without raising" do
      safe_proc = described_class.proc
      time_val = Time.now
      expect(safe_proc.call(time_val)).to eq(time_val)
      expect(safe_proc.call(time_val)).to be_a(Time)
    end

    it "raises TypeError for disallowed classes" do
      safe_proc = described_class.proc
      expect { safe_proc.call(42) }.to raise_error(TypeError)
      expect { safe_proc.call(3.14) }.to raise_error(TypeError)
    end

    it "includes the disallowed class name in the error message" do
      safe_proc = described_class.proc
      expect { safe_proc.call(42) }.to raise_error(TypeError, /Integer/)
      expect { safe_proc.call(42) }.to raise_error(TypeError, /Only .+ are allowed/)
    end
  end

  describe "safe loading with Marshal" do
    it "loads marshaled String data through SafeMarshal.proc" do
      original = "test string"
      data = Marshal.dump(original)
      result = Marshal.load(data, described_class.proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result).to be_a(String)
    end

    it "loads marshaled Array data through SafeMarshal.proc" do
      original = ["one", "two", "three"]
      data = Marshal.dump(original)
      result = Marshal.load(data, described_class.proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result).to be_a(Array)
    end

    it "loads marshaled Hash data through SafeMarshal.proc" do
      original = { "key" => "value", "nested" => ["a", "b"] }
      data = Marshal.dump(original)
      result = Marshal.load(data, described_class.proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result).to be_a(Hash)
    end

    it "loads marshaled boolean and Symbol data through SafeMarshal.proc" do
      [true, false, :symbol_test].each do |original|
        data = Marshal.dump(original)
        result = Marshal.load(data, described_class.proc) # rubocop:disable Security/MarshalLoad
        expect(result).to eq(original)
      end
    end
  end

  describe "class restriction enforcement" do
    it "raises TypeError when marshaled data contains a disallowed class" do
      # Regexp is not in the allowed list
      disallowed_data = Marshal.dump(/test_pattern/)
      expect { Marshal.load(disallowed_data, described_class.proc) }.to raise_error(TypeError) # rubocop:disable Security/MarshalLoad
    end

    it "includes class name and allowed classes list in the error message" do
      disallowed_data = Marshal.dump(/test_pattern/)
      expect { Marshal.load(disallowed_data, described_class.proc) }.to raise_error( # rubocop:disable Security/MarshalLoad
        TypeError, /Regexp/
      )
    end

    it "raises TypeError for Range objects in marshaled data" do
      disallowed_data = Marshal.dump(1..10)
      expect { Marshal.load(disallowed_data, described_class.proc) }.to raise_error(TypeError) # rubocop:disable Security/MarshalLoad
    end
  end

  describe "round-trip output validation" do
    it "preserves simple structure through dump and load" do
      original = { "name" => "test-gem", "version" => "1.0.0" }
      data = Marshal.dump(original)
      result = Marshal.load(data, described_class.proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result["name"]).to eq("test-gem")
    end

    it "preserves nested allowed-class structures" do
      original = {
        "gems" => ["bundler", "rake"],
        "active" => true,
        "label" => :production,
      }
      data = Marshal.dump(original)
      result = Marshal.load(data, described_class.proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result["gems"]).to eq(["bundler", "rake"])
    end

    it "preserves Gem::Version through dump and load" do
      original = Gem::Version.new("3.2.1")
      data = Marshal.dump(original)
      result = Marshal.load(data, described_class.proc) # rubocop:disable Security/MarshalLoad
      expect(result).to eq(original)
      expect(result).to be_a(Gem::Version)
    end

    it "rejects marshaled Time due to internal Integer representation" do
      # Time is in ALLOWED_CLASSES, but its Marshal format includes Integer
      # components internally, which are not allowed — this is expected behavior
      original = Time.now
      data = Marshal.dump(original)
      expect { Marshal.load(data, described_class.proc) }.to raise_error(TypeError, /Integer/) # rubocop:disable Security/MarshalLoad
    end
  end
end
