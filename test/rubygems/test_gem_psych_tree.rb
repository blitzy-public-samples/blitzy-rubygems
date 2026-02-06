# frozen_string_literal: true

require_relative "helper"
require "psych"
require "rubygems/psych_tree"

# Tests for Gem::NoAliasYAMLTree, a Psych::Visitors::YAMLTree subclass
# that customizes YAML emission for gemspec serialization.
#
# All tests guard on `defined?(Gem::NoAliasYAMLTree)` because the class
# is only defined when `Psych::Visitors` is available.
#
# Zero business logic in this file — every test invokes production code
# directly and asserts on its real output.

class TestGemPsychTree < Gem::TestCase
  # Verifies that Gem::NoAliasYAMLTree.create returns a properly typed
  # tree visitor that is both a NoAliasYAMLTree and a YAMLTree.
  def test_create_class_method
    return unless defined?(Gem::NoAliasYAMLTree)

    tree = Gem::NoAliasYAMLTree.create

    assert_kind_of Gem::NoAliasYAMLTree, tree
    assert_kind_of Psych::Visitors::YAMLTree, tree
  end

  # Verifies that visiting the string "=" produces a single-quoted scalar
  # in the YAML AST, which is the custom behavior of visit_String.
  def test_visit_string_equals
    return unless defined?(Gem::NoAliasYAMLTree)

    tree = Gem::NoAliasYAMLTree.create
    tree << "="

    stream = tree.tree
    document = stream.children.first
    assert_kind_of Psych::Nodes::Document, document

    scalar = document.children.first
    assert_equal "=", scalar.value
    assert_equal Psych::Nodes::Scalar::SINGLE_QUOTED, scalar.style
  end

  # Verifies that visiting a normal string (not "=") delegates to the
  # standard Psych visit path and does NOT apply single quoting.
  def test_visit_string_normal
    return unless defined?(Gem::NoAliasYAMLTree)

    tree = Gem::NoAliasYAMLTree.create
    tree << "hello world"

    stream = tree.tree
    document = stream.children.first
    assert_kind_of Psych::Nodes::Document, document

    scalar = document.children.first
    assert_equal "hello world", scalar.value
    refute_equal Psych::Nodes::Scalar::SINGLE_QUOTED, scalar.style
  end

  # Verifies that visit_Hash compacts nil values from the hash before
  # emitting, so keys with nil values are omitted from YAML output.
  def test_visit_hash_compacts_nil_values
    return unless defined?(Gem::NoAliasYAMLTree)

    tree = Gem::NoAliasYAMLTree.create
    tree << { "key" => "val", "nil_key" => nil }

    stream = tree.tree
    document = stream.children.first
    mapping = document.children.first
    assert_kind_of Psych::Nodes::Mapping, mapping

    # Extract keys from mapping children (alternating key, value nodes)
    keys = mapping.children.each_slice(2).map { |k, _v| k.value }
    assert_equal ["key"], keys
  end

  # Verifies that register is a noop — it does not raise and returns nil.
  # This eliminates YAML anchors/aliases from the serialized output.
  def test_register_is_noop
    return unless defined?(Gem::NoAliasYAMLTree)

    tree = Gem::NoAliasYAMLTree.create

    assert_respond_to tree, :register
    assert_nil tree.register(Object.new, Object.new)
  end

  # Verifies that Gem::NoAliasYAMLTree inherits from
  # Psych::Visitors::YAMLTree and responds to the create class method.
  def test_no_alias_yaml_tree_inherits_psych
    return unless defined?(Gem::NoAliasYAMLTree)

    assert_operator Gem::NoAliasYAMLTree, :<, Psych::Visitors::YAMLTree
    assert_respond_to Gem::NoAliasYAMLTree, :create
  end
end
