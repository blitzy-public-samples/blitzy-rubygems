# frozen_string_literal: true

require_relative "helper"
require "rubygems/unknown_command_spell_checker"
require "rubygems/command_manager"

class TestGemUnknownCommandSpellChecker < Gem::TestCase
  # Lightweight struct used as the error input for the spell checker.
  # Provides the :unknown_command attribute the production code reads.
  FakeError = Struct.new(:unknown_command)

  def setup
    super
    # Ensure a fresh CommandManager instance is available so that
    # the spell checker has a dictionary of known command names.
    Gem::CommandManager.reset
  end

  # ------------------------------------------------------------------ #
  # test_corrections_with_close_misspelling
  #   A near-miss command name like "instal" should yield an array
  #   that includes a suggestion containing the real command "install".
  # ------------------------------------------------------------------ #
  def test_corrections_with_close_misspelling
    error   = FakeError.new("instal")
    checker = Gem::UnknownCommandSpellChecker.new(error)

    corrections = checker.corrections

    assert_kind_of Array, corrections
    assert_includes corrections, "\"install\""
  end

  # ------------------------------------------------------------------ #
  # test_corrections_with_distant_misspelling
  #   A completely unrelated string should produce no suggestions.
  # ------------------------------------------------------------------ #
  def test_corrections_with_distant_misspelling
    error   = FakeError.new("xyzabc123")
    checker = Gem::UnknownCommandSpellChecker.new(error)

    corrections = checker.corrections

    assert_kind_of Array, corrections
    assert_empty corrections
  end

  # ------------------------------------------------------------------ #
  # test_corrections_caches_result
  #   The corrections array is memoized — calling it twice returns the
  #   exact same object (identical object_id).
  # ------------------------------------------------------------------ #
  def test_corrections_caches_result
    error   = FakeError.new("instal")
    checker = Gem::UnknownCommandSpellChecker.new(error)

    first_call  = checker.corrections
    second_call = checker.corrections

    assert_kind_of Array, first_call
    assert_equal first_call.object_id, second_call.object_id
  end

  # ------------------------------------------------------------------ #
  # test_error_accessor
  #   The :error reader exposes the original error object unchanged.
  # ------------------------------------------------------------------ #
  def test_error_accessor
    error   = FakeError.new("anything")
    checker = Gem::UnknownCommandSpellChecker.new(error)

    assert_respond_to checker, :error
    assert_equal error, checker.error
  end

  # ------------------------------------------------------------------ #
  # test_corrections_returns_inspected_strings
  #   Every element in the corrections array is a String that
  #   represents the inspected (quoted) form of a command name.
  # ------------------------------------------------------------------ #
  def test_corrections_returns_inspected_strings
    error   = FakeError.new("buil")
    checker = Gem::UnknownCommandSpellChecker.new(error)

    corrections = checker.corrections

    refute_empty corrections
    corrections.each do |suggestion|
      assert_kind_of String, suggestion
    end
  end
end
