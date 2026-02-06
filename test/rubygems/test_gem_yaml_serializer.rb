# frozen_string_literal: true

require_relative "helper"
require "rubygems/yaml_serializer"

class TestGemYAMLSerializer < Gem::TestCase
  #
  # Test that dump produces a valid YAML string from a simple hash.
  #
  def test_dump_simple_hash
    hash = { "key" => "value" }

    result = Gem::YAMLSerializer.dump(hash)

    assert_kind_of String, result
    assert_match(/key:/, result)
    assert_match(/value/, result)
  end

  #
  # Test that load parses a simple YAML string into the expected hash.
  #
  def test_load_simple_yaml
    yaml = "---\nkey: \"value\"\n"

    result = Gem::YAMLSerializer.load(yaml)

    assert_equal({ "key" => "value" }, result)
    assert_kind_of Hash, result
  end

  #
  # Test that dump followed by load preserves a simple multi-key hash.
  #
  def test_round_trip_simple
    hash = { "name" => "test", "version" => "1.0" }

    dumped = Gem::YAMLSerializer.dump(hash)
    loaded = Gem::YAMLSerializer.load(dumped)

    assert_equal hash, loaded
  end

  #
  # Test that dump followed by load preserves nested hash structures
  # with proper indentation handling.
  #
  def test_round_trip_nested_hash
    hash = { "outer" => { "inner" => "value" } }

    dumped = Gem::YAMLSerializer.dump(hash)
    loaded = Gem::YAMLSerializer.load(dumped)

    assert_equal "value", loaded["outer"]["inner"]
    assert_kind_of Hash, loaded["outer"]
  end

  #
  # Test that dump and load correctly handle hash values that are
  # non-empty arrays of strings.
  #
  def test_dump_with_array_values
    hash = { "deps" => ["a", "b", "c"] }

    result = Gem::YAMLSerializer.dump(hash)

    assert_match(/deps:/, result)

    loaded = Gem::YAMLSerializer.load(result)

    assert_equal ["a", "b", "c"], loaded["deps"]
  end

  #
  # Test that dump represents an empty array as [] and load
  # restores it back to an empty Ruby array.
  #
  def test_dump_empty_array
    hash = { "empty" => [] }

    result = Gem::YAMLSerializer.dump(hash)

    assert_match(/\[\]/, result)

    loaded = Gem::YAMLSerializer.load(result)

    assert_equal [], loaded["empty"]
  end

  #
  # Test that load handles an empty string input gracefully,
  # returning an empty hash.
  #
  def test_load_empty_string
    result = Gem::YAMLSerializer.load("")

    assert_kind_of Hash, result
    assert_empty result
  end

  #
  # Test that load strips inline comments from YAML values,
  # returning only the value portion before the comment marker.
  #
  def test_load_with_comments
    yaml = "---\nkey: value # comment\n"

    result = Gem::YAMLSerializer.load(yaml)

    assert_equal "value", result["key"]
    assert_kind_of Hash, result
  end

  #
  # Test that dump output always begins with the YAML document
  # separator "---".
  #
  def test_dump_starts_with_document_separator
    result = Gem::YAMLSerializer.dump({ "a" => "b" })

    assert result.start_with?("---")
    assert_kind_of String, result
  end

  #
  # Test that dump followed by load preserves string values
  # containing whitespace characters.
  #
  def test_round_trip_special_characters
    hash = { "key" => "value with spaces" }

    dumped = Gem::YAMLSerializer.dump(hash)
    loaded = Gem::YAMLSerializer.load(dumped)

    assert_equal hash, loaded
  end
end
