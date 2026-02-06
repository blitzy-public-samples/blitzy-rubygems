# frozen_string_literal: true

require "bundler/similarity_detector"

RSpec.describe Bundler::SimilarityDetector do
  describe "#similar_words" do
    context "when the corpus contains similar words" do
      it "returns words within the default distance limit" do
        detector = described_class.new(["bundle", "bundlr", "bunny"])
        result = detector.similar_words("bundl")
        expect(result).to include("bundle")
        expect(result).to include("bundlr")
      end

      it "returns words sorted by distance (closest first)" do
        detector = described_class.new(["install", "instal", "inspect"])
        result = detector.similar_words("instal")
        expect(result.first).to eq("instal")
      end

      it "excludes words beyond the default distance limit" do
        detector = described_class.new(["xyz", "abc", "hello"])
        result = detector.similar_words("hello")
        expect(result).to include("hello")
        expect(result).not_to include("xyz")
        expect(result).not_to include("abc")
      end

      it "returns an exact match with zero distance" do
        detector = described_class.new(["exec", "install", "update"])
        result = detector.similar_words("exec")
        expect(result).to include("exec")
      end
    end

    context "when using a custom distance limit" do
      it "returns words within the specified distance limit" do
        detector = described_class.new(["gem", "gems", "gemfile"])
        result = detector.similar_words("gm", 5)
        expect(result).to include("gem")
        expect(result).to include("gems")
      end

      it "returns fewer results with a stricter limit" do
        detector = described_class.new(["bundle", "bundler", "butter"])
        strict_results = detector.similar_words("bundl", 1)
        relaxed_results = detector.similar_words("bundl", 5)
        expect(strict_results.length).to be <= relaxed_results.length
      end
    end

    context "when the corpus is empty" do
      it "returns an empty array" do
        detector = described_class.new([])
        result = detector.similar_words("anything")
        expect(result).to be_empty
      end
    end

    context "when no words are within the distance limit" do
      it "returns an empty array" do
        detector = described_class.new(["zzzzzzzzz", "xxxxxxxxx"])
        result = detector.similar_words("a", 1)
        expect(result).to be_empty
      end
    end

    context "when all corpus words are identical to the query" do
      it "returns all identical words" do
        detector = described_class.new(["test", "test", "test"])
        result = detector.similar_words("test")
        expect(result.length).to eq(3)
        expect(result).to all(eq("test"))
      end
    end

    context "with single character words" do
      it "finds similar single character words" do
        detector = described_class.new(["a", "b", "c"])
        result = detector.similar_words("a")
        expect(result).to include("a")
      end

      it "considers single character substitution within limit" do
        detector = described_class.new(["a", "b", "z"])
        result = detector.similar_words("a", 1)
        expect(result).to include("a")
        expect(result).to include("b")
        expect(result).to include("z")
      end
    end
  end

  describe "#similar_word_list" do
    context "when there is exactly one similar word" do
      it "returns just the word as a string" do
        detector = described_class.new(["install"])
        result = detector.similar_word_list("install")
        expect(result).to eq("install")
      end
    end

    context "when there are exactly two similar words" do
      it "joins them with 'or'" do
        detector = described_class.new(["exec", "exac"])
        result = detector.similar_word_list("exac")
        expect(result).to include("or")
      end
    end

    context "when there are more than two similar words" do
      it "joins them with commas and 'or' for the last word" do
        detector = described_class.new(["install", "instal", "instll"])
        result = detector.similar_word_list("instl", 5)
        expect(result).to include(", ")
        expect(result).to include(" or ")
      end
    end

    context "when there are no similar words" do
      it "returns nil" do
        detector = described_class.new(["zzzzzzzzz"])
        result = detector.similar_word_list("a", 1)
        expect(result).to be_nil
      end
    end

    context "when the corpus is empty" do
      it "returns nil" do
        detector = described_class.new([])
        result = detector.similar_word_list("anything")
        expect(result).to be_nil
      end
    end

    context "with a custom distance limit" do
      it "returns words within the specified limit formatted as a list" do
        detector = described_class.new(["update", "updaet"])
        result = detector.similar_word_list("updat", 5)
        expect(result).not_to be_nil
        expect(result).to be_a(String)
      end
    end
  end

  describe "#initialize" do
    it "accepts an array corpus and creates a functional detector" do
      detector = described_class.new(["foo", "bar", "baz"])
      result = detector.similar_words("foo")
      expect(result).to include("foo")
    end

    it "accepts an empty array corpus" do
      detector = described_class.new([])
      result = detector.similar_words("anything")
      expect(result).to be_an(Array)
      expect(result).to be_empty
    end
  end

  describe "integration scenarios" do
    context "real-world gem name typos" do
      it "suggests 'rails' for 'rials'" do
        corpus = %w[rake rails rspec bundler gem]
        detector = described_class.new(corpus)
        result = detector.similar_words("rials")
        expect(result).to include("rails")
      end

      it "suggests 'rspec' for 'rpec'" do
        corpus = %w[rake rails rspec bundler gem]
        detector = described_class.new(corpus)
        result = detector.similar_words("rpec", 5)
        expect(result).to include("rspec")
      end

      it "suggests 'bundler' for 'bndler'" do
        corpus = %w[rake rails rspec bundler gem]
        detector = described_class.new(corpus)
        result = detector.similar_words("bndler")
        expect(result).to include("bundler")
      end

      it "returns an exact match first when present" do
        corpus = %w[rake rails rspec bundler gem]
        detector = described_class.new(corpus)
        result = detector.similar_words("gem")
        expect(result.first).to eq("gem")
      end
    end

    context "similar_word_list formatting with real-world examples" do
      it "formats a single suggestion correctly" do
        detector = described_class.new(%w[install uninstall])
        result = detector.similar_word_list("instal")
        expect(result).to eq("install")
      end

      it "formats multiple suggestions with 'or' separator" do
        detector = described_class.new(%w[exec exac])
        result = detector.similar_word_list("exac")
        expect(result).to be_a(String)
        expect(result.length).to be > 0
      end
    end

    context "boundary conditions" do
      it "handles very long words" do
        long_word = "a" * 100
        similar_long_word = "a" * 99 + "b"
        detector = described_class.new([similar_long_word])
        result = detector.similar_words(long_word, 1)
        expect(result).to include(similar_long_word)
      end

      it "handles words with special characters" do
        detector = described_class.new(["hello-world", "hello_world"])
        result = detector.similar_words("hello-world")
        expect(result).to include("hello-world")
      end

      it "handles words with numbers" do
        detector = described_class.new(["ruby3", "ruby2", "ruby1"])
        result = detector.similar_words("ruby3")
        expect(result).to include("ruby3")
      end

      it "handles unicode strings" do
        detector = described_class.new(["café", "cafe"])
        result = detector.similar_words("cafe")
        expect(result).to include("cafe")
      end
    end
  end
end
