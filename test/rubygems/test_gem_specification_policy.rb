# frozen_string_literal: true

require_relative "helper"
require "rubygems/specification_policy"

# Comprehensive unit tests for Gem::SpecificationPolicy.
# Tests exercise all public validation methods by creating real
# Gem::Specification instances with controlled attributes and invoking
# production SpecificationPolicy methods directly.
#
# Zero business logic: every line is an import, setup, production
# invocation, or assertion.
class TestGemSpecificationPolicy < Gem::TestCase
  def setup
    super
    # Build a baseline valid spec via the test harness helper.
    # files is intentionally empty to avoid file-system coupling
    # in unit-level checks.
    @spec = util_spec "testgem", "1.0.0" do |s|
      s.files = []
    end
  end

  # -------------------------------------------------------------------
  # 1. Full validate returns true for a well-formed specification
  # -------------------------------------------------------------------
  def test_validate_returns_true_for_valid_spec
    policy = Gem::SpecificationPolicy.new(@spec)
    result = nil
    use_ui @ui do
      result = policy.validate
    end
    assert_equal true, result
    assert_instance_of Gem::SpecificationPolicy, policy
  end

  # -------------------------------------------------------------------
  # 2. validate_name — empty string has no letters
  # -------------------------------------------------------------------
  def test_validate_name_raises_for_empty_name
    @spec.name = ""
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate
    end

    assert_match(/must include at least one letter/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 3. validate_name — symbol is not a string
  # -------------------------------------------------------------------
  def test_validate_name_raises_for_non_string_name
    @spec.name = :not_a_string
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate
    end

    assert_match(/must be a string/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 4. validate_name — digits-only name lacks letters
  # -------------------------------------------------------------------
  def test_validate_name_raises_for_name_without_letters
    @spec.name = "12345"
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate
    end

    assert_match(/must include at least one letter/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 5. validate_name — space and punctuation are invalid
  # -------------------------------------------------------------------
  def test_validate_name_raises_for_name_with_invalid_characters
    @spec.name = "invalid name!"
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate
    end

    assert_match(/can only include letters, numbers, dashes, and underscores/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 6. validate_name — leading period / dash / underscore rejected
  # -------------------------------------------------------------------
  def test_validate_name_raises_for_name_starting_with_special_character
    @spec.name = ".dotstart"
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate
    end

    assert_match(/cannot begin with a period, dash, or underscore/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 7. validate_name — well-formed name passes
  # -------------------------------------------------------------------
  def test_validate_name_passes_for_valid_name
    @spec.name = "valid-gem_name"
    policy = Gem::SpecificationPolicy.new(@spec)
    result = nil
    use_ui @ui do
      result = policy.validate
    end
    assert_equal true, result
    assert_equal "valid-gem_name", @spec.name
  end

  # -------------------------------------------------------------------
  # 8. validate_metadata — non-hash metadata rejected
  # -------------------------------------------------------------------
  def test_validate_metadata_raises_for_non_hash
    @spec.instance_variable_set(:@metadata, "not_a_hash")
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate_metadata
    end

    assert_match(/metadata must be a hash/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 9. validate_metadata — non-string key rejected
  # -------------------------------------------------------------------
  def test_validate_metadata_raises_for_non_string_keys
    @spec.instance_variable_set(:@metadata, { 1 => "value" })
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate_metadata
    end

    assert_match(/metadata keys must be a String/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 10. validate_metadata — oversized key rejected (> 128 chars)
  # -------------------------------------------------------------------
  def test_validate_metadata_raises_for_key_exceeding_128_chars
    long_key = "k" * 129
    @spec.metadata = { long_key => "value" }
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate_metadata
    end

    assert_match(/metadata key is too large/, e.message)
    assert_match(/129 > 128/, e.message)
  end

  # -------------------------------------------------------------------
  # 11. validate_metadata — non-string value rejected
  # -------------------------------------------------------------------
  def test_validate_metadata_raises_for_non_string_values
    @spec.instance_variable_set(:@metadata, { "key" => 123 })
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate_metadata
    end

    assert_match(/value must be a String/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 12. validate_metadata — oversized value rejected (> 1024 chars)
  # -------------------------------------------------------------------
  def test_validate_metadata_raises_for_value_exceeding_1024_chars
    long_value = "v" * 1025
    @spec.metadata = { "key" => long_value }
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate_metadata
    end

    assert_match(/value is too large/, e.message)
    assert_match(/1025 > 1024/, e.message)
  end

  # -------------------------------------------------------------------
  # 13. validate_metadata — invalid URI in link keys rejected
  # -------------------------------------------------------------------
  def test_validate_metadata_raises_for_invalid_uri_in_link_keys
    @spec.metadata = { "homepage_uri" => "not a valid url" }
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate_metadata
    end

    assert_match(/has invalid link/, e.message)
    assert_match(/homepage_uri/, e.message)
  end

  # -------------------------------------------------------------------
  # 14. validate_duplicate_dependencies — raises for duplicate deps
  # -------------------------------------------------------------------
  def test_validate_duplicate_dependencies_raises_for_duplicate_deps
    spec = util_spec "testgem", "1.0.0" do |s|
      s.files = []
      s.add_runtime_dependency "dupgem", ">= 1.0"
      s.add_runtime_dependency "dupgem", ">= 2.0"
    end
    policy = Gem::SpecificationPolicy.new(spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate_duplicate_dependencies
    end

    assert_match(/duplicate dependency on dupgem/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 15. validate_dependencies — warns on self-referencing dependency
  # -------------------------------------------------------------------
  def test_validate_dependencies_warns_on_self_referencing_dependency
    spec = util_spec "testgem", "1.0.0" do |s|
      s.files = []
      s.add_runtime_dependency "testgem", ">= 0"
    end
    policy = Gem::SpecificationPolicy.new(spec)

    use_ui @ui do
      policy.validate_dependencies
    end

    assert_match(/Self referencing dependency/, @ui.error)
    assert_match(/unnecessary and strongly discouraged/, @ui.error)
  end

  # -------------------------------------------------------------------
  # 16. validate_dependencies — warns on open-ended dependency
  # -------------------------------------------------------------------
  def test_validate_dependencies_warns_on_open_ended_dependency
    spec = util_spec "testgem", "1.0.0" do |s|
      s.files = []
      s.add_runtime_dependency "somegem", ">= 1.0"
    end
    policy = Gem::SpecificationPolicy.new(spec)

    use_ui @ui do
      policy.validate_dependencies
    end

    assert_match(/open-ended dependency on somegem/, @ui.error)
    assert_match(/not recommended/, @ui.error)
  end

  # -------------------------------------------------------------------
  # 17. validate_required_attributes — raises for missing required attr
  # -------------------------------------------------------------------
  def test_validate_required_attributes_raises_for_missing_required
    spec = util_spec "testgem", "1.0.0" do |s|
      s.files = []
    end
    # Setting to false bypasses validate_nil_attributes (which checks
    # for nil only) but still fails validate_required_attributes
    # (which checks for falsy values).
    spec.instance_variable_set(:@rubygems_version, false)
    policy = Gem::SpecificationPolicy.new(spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate
    end

    assert_match(/missing value for attribute rubygems_version/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 18. validate_require_paths — raises for empty paths
  # -------------------------------------------------------------------
  def test_validate_require_paths_raises_for_empty_paths
    @spec.require_paths = []
    policy = Gem::SpecificationPolicy.new(@spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate
    end

    assert_match(/must have at least one require_path/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 19. validate_platform — raises for non-Gem::Platform value
  # -------------------------------------------------------------------
  def test_validate_platform_raises_for_invalid_platform
    spec = util_spec "testgem", "1.0.0" do |s|
      s.files = []
    end
    # Bypass the platform= setter which auto-wraps in Gem::Platform
    spec.instance_variable_set(:@new_platform, "invalid_platform_string")
    policy = Gem::SpecificationPolicy.new(spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate
    end

    assert_match(/invalid platform/, e.message)
    assert_match(/see Gem::Platform/, e.message)
  end

  # -------------------------------------------------------------------
  # 20. validate_specification_version — non-integer rejected
  # -------------------------------------------------------------------
  def test_validate_specification_version_raises_for_non_integer
    spec = util_spec "testgem", "1.0.0" do |s|
      s.files = []
    end
    spec.instance_variable_set(:@specification_version, "not_an_integer")
    policy = Gem::SpecificationPolicy.new(spec)

    e = assert_raise Gem::InvalidSpecificationException do
      policy.validate
    end

    assert_match(/specification_version must be an Integer/, e.message)
    assert_match(/did you mean version/, e.message)
  end

  # -------------------------------------------------------------------
  # 21. validate with strict=true raises when warnings accumulate
  # -------------------------------------------------------------------
  def test_validate_strict_raises_on_warnings
    spec = util_spec "testgem", "1.0.0" do |s|
      s.files = []
      s.licenses = []
    end
    policy = Gem::SpecificationPolicy.new(spec)

    e = assert_raise Gem::InvalidSpecificationException do
      use_ui @ui do
        policy.validate(true)
      end
    end

    assert_match(/specification has warnings/, e.message)
    assert_kind_of Gem::InvalidSpecificationException, e
  end

  # -------------------------------------------------------------------
  # 22. validate_required_ruby_version — warns for default ">= 0"
  # -------------------------------------------------------------------
  def test_validate_required_ruby_version_warns_for_default_requirement
    spec = util_spec "testgem", "1.0.0" do |s|
      s.files = []
      # Intentionally not setting required_ruby_version;
      # it defaults to ">= 0" (DefaultRequirement).
    end
    policy = Gem::SpecificationPolicy.new(spec)

    use_ui @ui do
      policy.validate_required_ruby_version
    end

    assert_match(/make sure you specify the oldest ruby version/, @ui.error)
    assert_match(/required_ruby_version/, @ui.error)
  end

  # -------------------------------------------------------------------
  # 23. validate_licenses — warns when licenses list is empty
  # -------------------------------------------------------------------
  def test_validate_licenses_warns_for_missing_licenses
    spec = util_spec "testgem", "1.0.0" do |s|
      s.files = ["lib/code.rb"]
      s.licenses = []
      s.required_ruby_version = ">= 3.0"
    end
    policy = Gem::SpecificationPolicy.new(spec)

    use_ui @ui do
      policy.validate_optional(false)
    end

    assert_match(/licenses is empty/, @ui.error)
    assert_match(/spdx\.org/, @ui.error)
  end

  # -------------------------------------------------------------------
  # 24. packaging flag enables packaging-specific validation
  # -------------------------------------------------------------------
  def test_packaging_flag_triggers_packaging_checks
    spec = util_spec "testgem", "1.0.0" do |s|
      s.files = []
      s.rubygems_version = "0.0.0"
    end
    policy = Gem::SpecificationPolicy.new(spec)
    policy.packaging = true

    use_ui @ui do
      policy.validate
    end

    assert_equal true, policy.packaging
    assert_match(/expected RubyGems version #{Regexp.escape(Gem::VERSION)}, was 0.0.0/, @ui.error)
  end
end
