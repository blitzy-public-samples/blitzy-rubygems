# frozen_string_literal: true

require_relative "helper"
require "rubygems/specification_record"

class TestGemSpecificationRecord < Gem::TestCase
  def setup
    super

    # Create test gems in the test gem home using quick_gem helper.
    # quick_gem writes gemspec files to @gemhome/specifications/ and
    # writes lib files to @gemhome/gems/<name>-<version>/lib/.
    @spec_a1 = quick_gem "alpha", "1.0" do |s|
      s.files = %w[lib/alpha.rb]
      s.require_paths = %w[lib]
    end

    @spec_a2 = quick_gem "alpha", "2.0" do |s|
      s.files = %w[lib/alpha.rb]
      s.require_paths = %w[lib]
    end

    @spec_b1 = quick_gem "beta", "1.0" do |s|
      s.files = %w[lib/beta.rb]
      s.require_paths = %w[lib]
    end

    # Write actual library files so contains_requirable_file? can find them
    write_file File.join("gems", "alpha-1.0", "lib", "alpha.rb") do |io|
      io.puts "# alpha 1.0"
    end

    write_file File.join("gems", "alpha-2.0", "lib", "alpha.rb") do |io|
      io.puts "# alpha 2.0"
    end

    write_file File.join("gems", "beta-1.0", "lib", "beta.rb") do |io|
      io.puts "# beta 1.0"
    end

    # Create a fresh SpecificationRecord pointed at the test gem home
    @record = Gem::SpecificationRecord.from_path(@gemhome)
  end

  # ----------------------------------------------------------------
  # Class method: dirs_from
  # ----------------------------------------------------------------

  def test_dirs_from_converts_paths_to_specifications_subdirectories
    paths = ["/usr/local/gems", "/home/user/.gems", "/opt/rubygems"]
    result = Gem::SpecificationRecord.dirs_from(paths)

    assert_equal 3, result.size
    assert_equal "/usr/local/gems/specifications", result[0]
    assert_equal "/home/user/.gems/specifications", result[1]
    assert_equal "/opt/rubygems/specifications", result[2]
  end

  # ----------------------------------------------------------------
  # Class method: from_path
  # ----------------------------------------------------------------

  def test_from_path_creates_record_from_single_path
    record = Gem::SpecificationRecord.from_path(@gemhome)

    assert_instance_of Gem::SpecificationRecord, record
    assert_respond_to record, :stubs
    assert_respond_to record, :all
  end

  # ----------------------------------------------------------------
  # Instance method: initialize
  # ----------------------------------------------------------------

  def test_initialize_sets_up_empty_record_with_directories
    dirs = [File.join(@gemhome, "specifications")]
    record = Gem::SpecificationRecord.new(dirs)

    assert_instance_of Gem::SpecificationRecord, record
    assert_respond_to record, :stubs
    assert_respond_to record, :each
  end

  # ----------------------------------------------------------------
  # Instance method: stubs
  # ----------------------------------------------------------------

  def test_stubs_returns_stub_specifications_from_dirs
    stubs = @record.stubs

    assert_kind_of Array, stubs
    refute_empty stubs

    # Every returned stub should be a StubSpecification or a Specification
    stubs.each do |stub|
      assert_respond_to stub, :name
      assert_respond_to stub, :version
    end
  end

  # ----------------------------------------------------------------
  # Instance method: stubs_for
  # ----------------------------------------------------------------

  def test_stubs_for_returns_stubs_matching_gem_name
    stubs = @record.stubs_for("alpha")

    assert_kind_of Array, stubs
    refute_empty stubs

    stubs.each do |stub|
      assert_equal "alpha", stub.name
    end
  end

  def test_stubs_for_returns_empty_array_for_unknown_name
    stubs = @record.stubs_for("nonexistent_gem_xyz")

    assert_kind_of Array, stubs
    assert_empty stubs
  end

  # ----------------------------------------------------------------
  # Instance method: add_spec
  # ----------------------------------------------------------------

  def test_add_spec_adds_spec_and_maintains_sort_order
    new_spec = util_spec "gamma", "1.0"
    initial_count = @record.all.size

    @record.add_spec(new_spec)

    assert_includes @record.all, new_spec
    assert_equal initial_count + 1, @record.all.size

    # Verify sort order is maintained: names should be in sorted order
    names = @record.all.map(&:name)
    assert_equal names, names.sort
  end

  # ----------------------------------------------------------------
  # Instance method: remove_spec
  # ----------------------------------------------------------------

  def test_remove_spec_removes_spec_from_record
    # Ensure stubs are loaded and all is populated
    initial_all = @record.all.dup

    # Add a spec, then remove it
    new_spec = util_spec "delta", "1.0"
    @record.add_spec(new_spec)

    assert_includes @record.all, new_spec

    @record.remove_spec(new_spec)

    refute_includes @record.all, new_spec
    assert_equal initial_all.size, @record.all.size
  end

  # ----------------------------------------------------------------
  # Instance method: all
  # ----------------------------------------------------------------

  def test_all_returns_full_specifications
    all_specs = @record.all

    assert_kind_of Array, all_specs
    refute_empty all_specs

    # Each element should be a Gem::Specification
    all_specs.each do |spec|
      assert_kind_of Gem::Specification, spec
    end
  end

  # ----------------------------------------------------------------
  # Instance method: all_names
  # ----------------------------------------------------------------

  def test_all_names_returns_sorted_full_name_strings
    names = @record.all_names

    assert_kind_of Array, names
    refute_empty names

    # all_names should return full_name strings like "alpha-1.0", "alpha-2.0", "beta-1.0"
    names.each do |name|
      assert_kind_of String, name
    end

    assert_includes names, "alpha-1.0"
    assert_includes names, "alpha-2.0"
    assert_includes names, "beta-1.0"
  end

  # ----------------------------------------------------------------
  # Instance method: all= (setter)
  # ----------------------------------------------------------------

  def test_all_setter_replaces_all_specs_and_updates_stubs_by_name
    spec_x = util_spec "xray", "1.0"
    spec_y = util_spec "yankee", "2.0"

    @record.all = [spec_x, spec_y]

    all_specs = @record.all
    assert_equal 2, all_specs.size
    assert_includes all_specs, spec_x
    assert_includes all_specs, spec_y

    # stubs_for should reflect the new state
    xray_stubs = @record.stubs_for("xray")
    assert_equal 1, xray_stubs.size
    assert_equal "xray", xray_stubs.first.name
  end

  # ----------------------------------------------------------------
  # Enumerable: each
  # ----------------------------------------------------------------

  def test_each_enumerates_all_specs
    collected = []
    @record.each { |spec| collected << spec }

    assert_equal @record.all.size, collected.size
    refute_empty collected

    # Verify each element matches what all returns
    @record.all.each_with_index do |spec, i|
      assert_equal spec, collected[i]
    end
  end

  # ----------------------------------------------------------------
  # Instance method: find_all_by_name
  # ----------------------------------------------------------------

  def test_find_all_by_name_returns_specs_matching_name_and_version
    # Find alpha gems matching version >= 1.0
    matches = @record.find_all_by_name("alpha", ">= 1.0")

    assert_kind_of Array, matches
    refute_empty matches

    matches.each do |spec|
      assert_equal "alpha", spec.name
      assert spec.version >= Gem::Version.new("1.0")
    end

    # Find alpha gems matching exactly version 2.0
    exact_matches = @record.find_all_by_name("alpha", "= 2.0")
    assert_equal 1, exact_matches.size
    assert_equal Gem::Version.new("2.0"), exact_matches.first.version
  end

  def test_find_all_by_name_returns_empty_for_unmatched_name
    matches = @record.find_all_by_name("completely_unknown_gem")

    assert_kind_of Array, matches
    assert_empty matches
  end

  # ----------------------------------------------------------------
  # Instance method: find_by_path
  # ----------------------------------------------------------------

  def test_find_by_path_returns_spec_containing_requirable_file
    result = @record.find_by_path("beta")

    assert_kind_of Gem::Specification, result
    assert_equal "beta", result.name
  end

  def test_find_by_path_returns_nil_for_missing_path
    result = @record.find_by_path("totally_nonexistent_file_xyz")

    # find_by_path returns NOT_FOUND.to_spec which is nil when path not found
    assert_nil result
  end

  # ----------------------------------------------------------------
  # Instance method: find_inactive_by_path
  # ----------------------------------------------------------------

  def test_find_inactive_by_path_returns_non_activated_spec
    # In the test environment, gems are not activated by default,
    # so find_inactive_by_path should be able to find our beta gem.
    result = @record.find_inactive_by_path("beta")

    assert_kind_of Gem::Specification, result
    assert_equal "beta", result.name
  end

  # ----------------------------------------------------------------
  # Instance method: find_active_stub_by_path
  # ----------------------------------------------------------------

  def test_find_active_stub_by_path_returns_nil_when_no_active_stub
    # No gems are activated in the test environment, so this should return nil.
    result = @record.find_active_stub_by_path("beta")

    assert_nil result
  end

  # ----------------------------------------------------------------
  # Instance method: latest_specs
  # ----------------------------------------------------------------

  def test_latest_specs_returns_latest_version_specs
    latest = @record.latest_specs(false)

    assert_kind_of Array, latest
    refute_empty latest

    # For gem "alpha", only the latest version (2.0) should appear
    alpha_latest = latest.select { |s| s.name == "alpha" }
    assert_equal 1, alpha_latest.size
    assert_equal Gem::Version.new("2.0"), alpha_latest.first.version

    # For gem "beta", version 1.0 should be present (only version)
    beta_latest = latest.select { |s| s.name == "beta" }
    assert_equal 1, beta_latest.size
    assert_equal Gem::Version.new("1.0"), beta_latest.first.version
  end

  # ----------------------------------------------------------------
  # Instance method: latest_spec_for
  # ----------------------------------------------------------------

  def test_latest_spec_for_returns_latest_spec_for_given_name
    latest_alpha = @record.latest_spec_for("alpha")

    refute_nil latest_alpha
    assert_equal "alpha", latest_alpha.name
    assert_equal Gem::Version.new("2.0"), latest_alpha.version
  end

  # ----------------------------------------------------------------
  # Instance method: stubs_for_pattern
  # ----------------------------------------------------------------

  def test_stubs_for_pattern_matches_pattern
    # Match all gemspec files with the "alpha" prefix
    stubs = @record.stubs_for_pattern("alpha-*.gemspec")

    assert_kind_of Array, stubs
    refute_empty stubs

    stubs.each do |stub|
      assert_equal "alpha", stub.name
    end

    # Match all gemspec files
    all_stubs = @record.stubs_for_pattern("*.gemspec")
    assert all_stubs.size >= stubs.size
  end
end
