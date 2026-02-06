# frozen_string_literal: true

require "bundler/yaml_serializer"

RSpec.describe Bundler::YAMLSerializer do
  subject(:serializer) { Bundler::YAMLSerializer }

  describe "#dump" do
    it "works for simple hash" do
      hash = { "Q" => "Where does Thursday come before Wednesday? In the dictionary. :P" }

      expected = <<~YAML
          ---
          Q: "Where does Thursday come before Wednesday? In the dictionary. :P"
      YAML

      expect(serializer.dump(hash)).to eq(expected)
    end

    it "handles nested hash" do
      hash = {
        "nice-one" => {
          "read_ahead" => "All generalizations are false, including this one",
        },
      }

      expected = <<~YAML
          ---
          nice-one:
            read_ahead: "All generalizations are false, including this one"
      YAML

      expect(serializer.dump(hash)).to eq(expected)
    end

    it "array inside an hash" do
      hash = {
        "nested_hash" => {
          "contains_array" => [
            "Jack and Jill went up the hill",
            "To fetch a pail of water.",
            "Jack fell down and broke his crown,",
            "And Jill came tumbling after.",
          ],
        },
      }

      expected = <<~YAML
        ---
        nested_hash:
          contains_array:
          - "Jack and Jill went up the hill"
          - "To fetch a pail of water."
          - "Jack fell down and broke his crown,"
          - "And Jill came tumbling after."
      YAML

      expect(serializer.dump(hash)).to eq(expected)
    end

    it "handles empty array" do
      hash = {
        "empty_array" => [],
      }

      expected = <<~YAML
        ---
        empty_array: []
      YAML

      expect(serializer.dump(hash)).to eq(expected)
    end
  end

  describe "#load" do
    it "works for simple hash" do
      yaml = <<~YAML
        ---
        Jon: "Air is free dude!"
        Jack: "Yes.. until you buy a bag of chips!"
      YAML

      hash = {
        "Jon" => "Air is free dude!",
        "Jack" => "Yes.. until you buy a bag of chips!",
      }

      expect(serializer.load(yaml)).to eq(hash)
    end

    it "works for nested hash" do
      yaml = <<~YAML
        ---
        baa:
          baa: "black sheep"
          have: "you any wool?"
          yes: "merry have I"
        three: "bags full"
      YAML

      hash = {
        "baa" => {
          "baa" => "black sheep",
          "have" => "you any wool?",
          "yes" => "merry have I",
        },
        "three" => "bags full",
      }

      expect(serializer.load(yaml)).to eq(hash)
    end

    it "handles colon in key/value" do
      yaml = <<~YAML
        BUNDLE_MIRROR__HTTPS://RUBYGEMS__ORG/: http://example-mirror.rubygems.org
      YAML

      expect(serializer.load(yaml)).to eq("BUNDLE_MIRROR__HTTPS://RUBYGEMS__ORG/" => "http://example-mirror.rubygems.org")
    end

    it "handles arrays inside hashes" do
      yaml = <<~YAML
        ---
        nested_hash:
          contains_array:
          - "Why shouldn't you write with a broken pencil?"
          - "Because it's pointless!"
      YAML

      hash = {
        "nested_hash" => {
          "contains_array" => [
            "Why shouldn't you write with a broken pencil?",
            "Because it's pointless!",
          ],
        },
      }

      expect(serializer.load(yaml)).to eq(hash)
    end

    it "handles windows-style CRLF line endings" do
      yaml = <<~YAML.gsub("\n", "\r\n")
        ---
        nested_hash:
          contains_array:
          - "Why shouldn't you write with a broken pencil?"
          - "Because it's pointless!"
          - oh so silly
      YAML

      hash = {
        "nested_hash" => {
          "contains_array" => [
            "Why shouldn't you write with a broken pencil?",
            "Because it's pointless!",
            "oh so silly",
          ],
        },
      }

      expect(serializer.load(yaml)).to eq(hash)
    end

    it "handles empty array" do
      yaml = <<~YAML
        ---
        empty_array: []
      YAML

      hash = {
        "empty_array" => [],
      }

      expect(serializer.load(yaml)).to eq(hash)
    end

    it "skip commented out words" do
      yaml = <<~YAML
        ---
        foo: bar
        buzz: foo # bar
      YAML

      hash = {
        "foo" => "bar",
        "buzz" => "foo",
      }

      expect(serializer.load(yaml)).to eq(hash)
    end
  end

  describe "against yaml lib" do
    let(:hash) do
      {
        "a_joke" => {
          "my-stand" => "I can totally keep secrets",
          "but" => "The people I tell them to can't :P",
          "wouldn't it be funny if this string were empty?" => "",
        },
        "more" => {
          "first" => [
            "Can a kangaroo jump higher than a house?",
            "Of course, a house doesn't jump at all.",
          ],
          "second" => [
            "What did the sea say to the sand?",
            "Nothing, it simply waved.",
          ],
          "array with empty string" => [""],
        },
        "sales" => {
          "item" => "A Parachute",
          "description" => "Only used once, never opened.",
        },
        "one-more" => "I'd tell you a chemistry joke but I know I wouldn't get a reaction.",
      }
    end

    context "#load" do
      it "retrieves the original hash" do
        require "yaml"
        expect(serializer.load(YAML.dump(hash))).to eq(hash)
      end
    end

    context "#dump" do
      it "retrieves the original hash" do
        require "yaml"
        expect(YAML.load(serializer.dump(hash))).to eq(hash)
      end
    end
  end

  context "with special characters" do
    it "round-trips strings containing colons in values" do
      hash = {"mirror" => "https://rubygems.org", "setting" => "host:3000"}
      result = serializer.load(serializer.dump(hash))
      expect(result["mirror"]).to eq("https://rubygems.org")
      expect(result["setting"]).to eq("host:3000")
    end

    it "round-trips strings containing single quotes in values" do
      hash = {"message" => "it's a test", "note" => "say 'hello'"}
      result = serializer.load(serializer.dump(hash))
      expect(result["message"]).to eq("it's a test")
      expect(result["note"]).to eq("say 'hello'")
    end

    it "applies comment stripping to hash symbols in values during round-trip" do
      hash = {"tagged" => "item #5", "plain" => "safe"}
      dumped = serializer.dump(hash)
      loaded = serializer.load(dumped)
      expect(loaded["plain"]).to eq("safe")
      expect(loaded["tagged"]).to eq("item")
    end

    it "round-trips strings containing Unicode characters" do
      hash = {"place" => "caf\u00e9", "city" => "Z\u00fcrich"}
      result = serializer.load(serializer.dump(hash))
      expect(result["place"]).to eq("caf\u00e9")
      expect(result["city"]).to eq("Z\u00fcrich")
    end

    it "normalizes embedded newlines and tabs to single spaces during dump" do
      hash = {"multiline" => "line1\nline2\ttabbed"}
      dumped = serializer.dump(hash)
      result = serializer.load(dumped)
      expect(result["multiline"]).to eq("line1 line2 tabbed")
      expect(dumped).to include("line1 line2 tabbed")
    end
  end

  context "with empty input" do
    it "dumps an empty hash to a valid YAML document" do
      result = serializer.dump({})
      expect(result).to start_with("---")
      expect(result.strip).to eq("---")
    end

    it "loads an empty string to an empty hash" do
      result = serializer.load("")
      expect(result).to be_a(Hash)
      expect(result).to be_empty
    end

    it "loads whitespace-only input to an empty hash" do
      result = serializer.load("   \n  \n")
      expect(result).to be_a(Hash)
      expect(result).to be_empty
    end

    it "loads YAML document separator only to an empty hash" do
      bare = serializer.load("---")
      with_newline = serializer.load("---\n")
      expect(bare).to eq({})
      expect(with_newline).to eq({})
    end
  end

  context "with malformed YAML" do
    it "handles improperly indented nested values by adjusting depth" do
      yaml = "parent:\n child: value\n"
      result = serializer.load(yaml)
      expect(result).to have_key("parent")
      expect(result).to have_key("child")
    end

    it "treats keys with missing values as empty nested hashes" do
      yaml = "parent:\nsibling: present\n"
      result = serializer.load(yaml)
      expect(result["parent"]).to eq({})
      expect(result["sibling"]).to eq("present")
    end

    it "silently ignores lines without key-value colon separators" do
      yaml = "no_colon_here\nvalid_key: valid_value\n"
      result = serializer.load(yaml)
      expect(result).to eq({"valid_key" => "valid_value"})
      expect(result).not_to have_key("no_colon_here")
    end
  end

  context "round-trip edge cases" do
    it "round-trips deeply nested hash structures of three or more levels" do
      hash = {"level1" => {"level2" => {"level3" => "deep_value"}}}
      result = serializer.load(serializer.dump(hash))
      expect(result).to eq(hash)
      expect(result.dig("level1", "level2", "level3")).to eq("deep_value")
    end

    it "round-trips boolean-like string values preserving them as strings" do
      hash = {"enabled" => "true", "disabled" => "false", "confirm" => "yes", "deny" => "no"}
      result = serializer.load(serializer.dump(hash))
      expect(result).to eq(hash)
      expect(result.values).to all(be_a(String))
    end

    it "round-trips numeric string values preserving them as strings" do
      hash = {"count" => "42", "version" => "3.14", "zero" => "0"}
      result = serializer.load(serializer.dump(hash))
      expect(result).to eq(hash)
      expect(result.values).to all(be_a(String))
    end
  end
end
