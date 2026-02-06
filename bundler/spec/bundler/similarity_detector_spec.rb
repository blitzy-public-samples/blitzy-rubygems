# frozen_string_literal: true

require "spec_helper"
require "bundler/similarity_detector"

RSpec.describe Bundler::SimilarityDetector do
  describe "#initialize" do
    it "creates a functional detector from a corpus array" do
      detector = described_class.new(["foo", "bar", "baz"])
      expect(detector).to be_a(described_class)
      expect(detector).to respond_to(:similar_words)
      expect(detector).to respond_to(:similar_word_list)
    end

    it "accepts an empty array as corpus" do
      detector = described_class.new([])
      expect(detector).to be_a(described_class)
      expect(detector.similar_words("anything")).to eq([])
    end
  end

  describe "#similar_words" do
    let(:corpus) { %w[install update exec config] }
    let(:detector) { described_class.new(corpus) }

    it "returns similar words within the default distance limit of 3" do
      result = detector.similar_words("instal")
      expect(result).to be_an(Array)
      expect(result).to include("install")
    end

    it "excludes words beyond the default distance limit" do
      result = detector.similar_words("instal")
      expect(result).not_to include("update")
      expect(result).not_to include("config")
      expect(result).not_to include("exec")
    end

    it "returns results sorted by distance with closest match first" do
      sorted_detector = described_class.new(%w[install instal instll])
      result = sorted_detector.similar_words("instal")
      expect(result.first).to eq("instal")
      expect(result.length).to eq(3)
    end

    context "with a custom distance limit" do
      it "returns words within the specified limit" do
        result = detector.similar_words("instal", 2)
        expect(result).to include("install")
        expect(result).to be_an(Array)
      end

      it "returns fewer or equal results with a stricter limit" do
        strict = detector.similar_words("instal", 1)
        relaxed = detector.similar_words("instal", 3)
        expect(strict).to be_empty
        expect(relaxed).to include("install")
      end
    end

    context "when no words are within the distance limit" do
      it "returns an empty array for distant words" do
        result = detector.similar_words("zzzzzzzzz", 1)
        expect(result).to be_an(Array)
        expect(result).to be_empty
      end
    end
  end

  describe "#similar_word_list" do
    context "with a single match" do
      it "returns just the word as a string" do
        detector = described_class.new(%w[install zzzzzzzzz])
        result = detector.similar_word_list("instal")
        expect(result).to eq("install")
        expect(result).to be_a(String)
      end
    end

    context "with two matches" do
      it "joins them with 'or'" do
        detector = described_class.new(%w[abc abd])
        result = detector.similar_word_list("abc")
        expect(result).to include(" or ")
        expect(result).to be_a(String)
      end
    end

    context "with three or more matches" do
      it "joins with commas and 'or' for the last word" do
        detector = described_class.new(%w[abc abd abe])
        result = detector.similar_word_list("abc")
        expect(result).to include(", ")
        expect(result).to include(" or ")
      end
    end

    context "with no matches" do
      it "returns nil when no words are within the distance" do
        detector = described_class.new(%w[zzzzzzzzz])
        result = detector.similar_word_list("a", 1)
        expect(result).to be_nil
      end

      it "returns nil for an empty corpus" do
        detector = described_class.new([])
        result = detector.similar_word_list("anything")
        expect(result).to be_nil
      end
    end
  end

  context "similar string detection" do
    let(:corpus) { %w[install update exec config] }
    let(:detector) { described_class.new(corpus) }

    it "finds close misspellings and returns suggestions" do
      result = detector.similar_words("instal")
      expect(result).to include("install")
      expect(result).not_to include("update")
    end

    it "respects distance threshold filtering" do
      strict_result = detector.similar_words("instal", 1)
      relaxed_result = detector.similar_words("instal", 3)
      expect(strict_result).to be_empty
      expect(relaxed_result).to include("install")
    end
  end

  context "identical strings" do
    it "returns the identical word since distance is zero" do
      detector = described_class.new(%w[install update exec])
      result = detector.similar_words("install")
      expect(result).to include("install")
      expect(result.first).to eq("install")
    end

    it "returns all identical entries when corpus contains duplicates" do
      detector = described_class.new(%w[test test test])
      result = detector.similar_words("test")
      expect(result.length).to eq(3)
      expect(result).to all(eq("test"))
    end
  end

  context "completely different strings" do
    it "returns no suggestions for very different input" do
      detector = described_class.new(%w[install update exec config])
      result = detector.similar_words("zzz", 1)
      expect(result).to be_an(Array)
      expect(result).to be_empty
    end

    it "returns no suggestions for distant multi-character input" do
      detector = described_class.new(%w[alpha beta gamma])
      result = detector.similar_words("xyz", 1)
      expect(result).to be_empty
      expect(detector.similar_word_list("xyz", 1)).to be_nil
    end
  end

  context "empty corpus" do
    let(:detector) { described_class.new([]) }

    it "returns empty array from similar_words" do
      result = detector.similar_words("anything")
      expect(result).to be_an(Array)
      expect(result).to be_empty
    end

    it "returns nil from similar_word_list" do
      result = detector.similar_word_list("anything")
      expect(result).to be_nil
      expect(detector.similar_word_list("test", 1)).to be_nil
    end
  end

  context "real-world gem name typos" do
    let(:corpus) { %w[rake rails rspec bundler gem] }
    let(:detector) { described_class.new(corpus) }

    it "suggests 'rails' for 'rials'" do
      result = detector.similar_words("rials")
      expect(result).to include("rails")
      expect(result).to be_an(Array)
    end

    it "suggests 'bundler' for 'bndler'" do
      result = detector.similar_words("bndler")
      expect(result).to include("bundler")
      expect(result).to be_an(Array)
    end

    it "returns an exact match first when present" do
      result = detector.similar_words("gem")
      expect(result.first).to eq("gem")
      expect(result).to include("gem")
    end
  end

  context "boundary conditions" do
    it "handles single character corpus words" do
      detector = described_class.new(%w[a b c])
      result = detector.similar_words("a")
      expect(result).to include("a")
      expect(result).to be_an(Array)
    end

    it "handles words with special characters" do
      detector = described_class.new(["hello-world", "hello_world"])
      result = detector.similar_words("hello-world")
      expect(result).to include("hello-world")
      expect(result).to include("hello_world")
    end

    it "handles very long words" do
      long_word = "a" * 50
      similar_word = "a" * 49 + "b"
      detector = described_class.new([similar_word])
      result = detector.similar_words(long_word, 1)
      expect(result).to include(similar_word)
      expect(result.length).to eq(1)
    end

    it "handles words with numeric characters" do
      detector = described_class.new(%w[ruby3 ruby2 ruby1])
      result = detector.similar_words("ruby3")
      expect(result).to include("ruby3")
      expect(result.length).to be >= 1
    end
  end
end
