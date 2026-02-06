# frozen_string_literal: true

require_relative "helper"
require "rubygems/specification"

class TestGemBasicSpecification < Gem::TestCase
  def setup
    super

    @spec = util_spec "my_gem", "1.0" do |s|
      s.files = %w[lib/my_gem.rb]
      s.require_paths = %w[lib]
      s.license = "MIT"
    end

    # Write the spec file so loaded_from is set and base_dir/gems_dir resolve
    written_path = write_file @spec.spec_file do |io|
      io.write @spec.to_ruby_for_cache
    end
    @spec.loaded_from = written_path

    @platform_spec = util_spec "plat_gem", "2.0" do |s|
      s.platform = Gem::Platform.new("x86-linux")
      s.files = %w[lib/plat_gem.rb]
      s.require_paths = %w[lib]
      s.license = "MIT"
    end

    plat_written = write_file @platform_spec.spec_file do |io|
      io.write @platform_spec.to_ruby_for_cache
    end
    @platform_spec.loaded_from = plat_written
  end

  # (1) full_name returns 'name-version' for ruby platform
  def test_full_name_ruby_platform
    result = @spec.full_name
    assert_equal "my_gem-1.0", result
    assert_kind_of String, result
  end

  # (2) full_name returns 'name-version-platform' for non-ruby platform
  def test_full_name_non_ruby_platform
    result = @platform_spec.full_name
    assert_equal "plat_gem-2.0-x86-linux", result
    assert_match(/\Aplat_gem-2\.0-/, result)
  end

  # (3) full_gem_path returns expanded path joining gems_dir and full_name
  def test_full_gem_path
    path = @spec.full_gem_path
    expected = File.expand_path(File.join(@spec.gems_dir, @spec.full_name))
    assert_equal expected, path
    assert_kind_of String, path
  end

  # (4) gem_dir matches full_gem_path
  def test_gem_dir_matches_full_gem_path
    gem_dir = @spec.gem_dir
    full_gem_path = @spec.full_gem_path
    assert_equal full_gem_path, gem_dir
    assert_kind_of String, gem_dir
  end

  # (5) loaded_from accessor reads and writes
  def test_loaded_from_accessor
    spec = util_spec "accessor_test", "1.0"
    original_loaded_from = spec.loaded_from

    new_path = File.join(@tempdir, "custom", "path.gemspec")
    spec.loaded_from = new_path
    assert_equal new_path, spec.loaded_from
    assert_not_equal original_loaded_from, spec.loaded_from unless original_loaded_from == new_path
  end

  # (6) base_dir returns gem home base directory
  def test_base_dir
    base = @spec.base_dir
    assert_kind_of String, base
    # The base_dir should be parent of "specifications" where loaded_from resides
    assert_equal File.dirname(File.dirname(@spec.loaded_from)), base
  end

  # (7) gems_dir returns gems subdirectory under base_dir
  def test_gems_dir
    gems = @spec.gems_dir
    assert_kind_of String, gems
    assert_equal File.join(@spec.base_dir, "gems"), gems
  end

  # (8) extension_dir returns path under extensions directory
  def test_extension_dir
    ext_dir = @spec.extension_dir
    assert_kind_of String, ext_dir
    assert_match(/extensions/, ext_dir)
    assert ext_dir.end_with?(@spec.full_name), "extension_dir should end with full_name"
  end

  # (9) extensions_dir uses Gem.extension_api_version
  def test_extensions_dir
    ext_dirs = @spec.extensions_dir
    assert_kind_of String, ext_dirs
    # When default_ext_dir_for returns nil (the default), extensions_dir should
    # be constructed with the extension_api_version component
    api_version = Gem.extension_api_version
    assert_match(/#{Regexp.escape(api_version)}/, ext_dirs)
    assert_match(/extensions/, ext_dirs)
  end

  # (10) gem_build_complete_path is inside extension_dir
  def test_gem_build_complete_path
    build_complete = @spec.gem_build_complete_path
    ext_dir = @spec.extension_dir
    assert_kind_of String, build_complete
    assert_equal File.join(ext_dir, "gem.build_complete"), build_complete
    assert build_complete.start_with?(ext_dir), "gem_build_complete_path should start with extension_dir"
  end

  # (11) default_gem? returns true when loaded_from is in default_specifications_dir
  def test_default_gem_true
    default_spec = new_default_spec("default_test", "1.0", nil, "lib/default_test.rb")
    assert_equal true, default_spec.default_gem?
    assert_equal File.dirname(default_spec.loaded_from), Gem.default_specifications_dir
  end

  # (12) default_gem? returns false for normal gems
  def test_default_gem_false
    assert_equal false, @spec.default_gem?
    refute @spec.default_gem?
  end

  # (13) default_gem_priority returns 1 for default gems
  def test_default_gem_priority_default
    default_spec = new_default_spec("priority_default", "1.0", nil, "lib/priority_default.rb")
    priority = default_spec.default_gem_priority
    assert_equal 1, priority
    assert default_spec.default_gem?
  end

  # (14) default_gem_priority returns -1 for regular gems
  def test_default_gem_priority_regular
    priority = @spec.default_gem_priority
    assert_equal(-1, priority)
    refute @spec.default_gem?
  end

  # (15) full_require_paths includes lib directory
  def test_full_require_paths
    paths = @spec.full_require_paths
    assert_kind_of Array, paths
    expected_lib = File.join(@spec.full_gem_path, "lib")
    assert_includes paths, expected_lib
  end

  # (16) require_paths without extensions returns raw paths
  def test_require_paths_without_extensions
    # @spec has no extensions, so require_paths should equal raw_require_paths
    req_paths = @spec.require_paths
    raw_paths = @spec.raw_require_paths
    assert_equal raw_paths, req_paths
    assert_includes req_paths, "lib"
  end

  # (17) source_paths returns require paths
  def test_source_paths
    src_paths = @spec.source_paths
    assert_kind_of Array, src_paths
    assert_includes src_paths, "lib"
    # For spec without extensions, source_paths matches raw_require_paths
    assert_equal @spec.raw_require_paths, src_paths
  end

  # (18) lib_dirs_glob constructs correct glob pattern
  def test_lib_dirs_glob
    glob = @spec.lib_dirs_glob
    assert_kind_of String, glob
    assert_equal "#{@spec.full_gem_path}/lib", glob
  end

  # (19) contains_requirable_file? finds files in require paths
  def test_contains_requirable_file_found
    spec = util_spec "requirable", "1.0" do |s|
      s.files = %w[lib/requirable.rb]
      s.require_paths = %w[lib]
    end

    written_spec_path = write_file spec.spec_file do |io|
      io.write spec.to_ruby_for_cache
    end
    spec.loaded_from = written_spec_path

    # Create the actual .rb file in the gem's lib directory
    lib_file = File.join(spec.full_gem_path, "lib", "requirable.rb")
    FileUtils.mkdir_p File.dirname(lib_file)
    File.write(lib_file, "# requirable")

    result = spec.contains_requirable_file?("requirable")
    assert_equal true, result
    assert spec.contains_requirable_file?("requirable")
  end

  # (20) contains_requirable_file? returns false for missing files
  def test_contains_requirable_file_missing
    result = @spec.contains_requirable_file?("nonexistent_file_xyz")
    assert_equal false, result
    refute @spec.contains_requirable_file?("nonexistent_file_xyz")
  end

  # (21) installable_on_platform? returns true for ruby platform
  def test_installable_on_platform_ruby
    result = @spec.installable_on_platform?(Gem::Platform.local)
    assert_equal true, result
    assert @spec.installable_on_platform?(Gem::Platform::RUBY)
  end

  # (22) this returns self
  def test_this_returns_self
    result = @spec.this
    assert_same @spec, result
    assert_equal @spec.object_id, result.object_id
  end

  # (23) abstract methods on bare BasicSpecification raise NotImplementedError
  def test_abstract_methods_raise_not_implemented
    bs = Gem::BasicSpecification.new

    assert_raise(NotImplementedError) { bs.activated? }
    assert_raise(NotImplementedError) { bs.base_dir }
    assert_raise(NotImplementedError) { bs.gems_dir }
    assert_raise(NotImplementedError) { bs.name }
    assert_raise(NotImplementedError) { bs.platform }
    assert_raise(NotImplementedError) { bs.raw_require_paths }
    assert_raise(NotImplementedError) { bs.to_spec }
    assert_raise(NotImplementedError) { bs.version }
    assert_raise(NotImplementedError) { bs.stubbed? }
  end

  # (24) full_name_with_location returns full_name when base_dir equals Gem.dir
  def test_full_name_with_location
    # When base_dir == Gem.dir, returns full_name only
    spec_in_gemhome = util_spec "loc_gem", "1.0" do |s|
      s.files = %w[lib/loc_gem.rb]
      s.require_paths = %w[lib]
    end

    gemhome_spec_path = File.join(@gemhome, "specifications", "loc_gem-1.0.gemspec")
    FileUtils.mkdir_p File.dirname(gemhome_spec_path)
    File.write(gemhome_spec_path, spec_in_gemhome.to_ruby_for_cache)
    spec_in_gemhome.loaded_from = gemhome_spec_path

    result = spec_in_gemhome.full_name_with_location
    assert_equal "loc_gem-1.0", result

    # When base_dir != Gem.dir, includes location info
    alt_base = File.join(@tempdir, "alt_gem_home")
    alt_spec_path = File.join(alt_base, "specifications", "loc_gem-1.0.gemspec")
    FileUtils.mkdir_p File.dirname(alt_spec_path)
    File.write(alt_spec_path, spec_in_gemhome.to_ruby_for_cache)

    spec_in_alt = util_spec "loc_gem", "1.0" do |s|
      s.files = %w[lib/loc_gem.rb]
      s.require_paths = %w[lib]
    end
    spec_in_alt.loaded_from = alt_spec_path

    alt_result = spec_in_alt.full_name_with_location
    assert_match(/loc_gem-1\.0 in/, alt_result)
    assert_match(/alt_gem_home/, alt_result)
  end

  # (25) datadir returns the data directory path for the gem
  def test_datadir
    result = nil
    # datadir is deprecated, silence the warning
    _out, _err = capture_output do
      result = @spec.datadir
    end
    expected = File.expand_path(File.join(@spec.gems_dir, @spec.full_name, "data", @spec.name))
    assert_equal expected, result
    assert_kind_of String, result
  end

  # Additional: lib_dirs_glob with multiple require_paths uses brace expansion
  def test_lib_dirs_glob_multiple_require_paths
    multi_spec = util_spec "multi_path", "1.0" do |s|
      s.files = %w[lib/multi.rb ext/multi_ext.rb]
      s.require_paths = %w[lib ext]
    end

    written_path = write_file multi_spec.spec_file do |io|
      io.write multi_spec.to_ruby_for_cache
    end
    multi_spec.loaded_from = written_path

    glob = multi_spec.lib_dirs_glob
    assert_kind_of String, glob
    assert_match("{lib,ext}", glob)
    assert glob.start_with?(multi_spec.full_gem_path)
  end

  # Additional: installable_on_platform? returns true for matching platform
  def test_installable_on_platform_matching
    plat = Gem::Platform.new("x86-linux")
    result = @platform_spec.installable_on_platform?(plat)
    assert_equal true, result
    assert @platform_spec.installable_on_platform?(plat)
  end

  # Additional: installable_on_platform? returns false for non-matching platform
  def test_installable_on_platform_non_matching
    other_plat = Gem::Platform.new("arm-darwin")
    result = @platform_spec.installable_on_platform?(other_plat)
    # Platform matching relies on Gem::Platform === comparison
    # x86-linux does not match arm-darwin
    refute result
    assert_kind_of FalseClass, result unless result
  end

  # Additional: extension_dir with custom base_dir writer
  def test_extension_dir_custom_base
    spec = util_spec "ext_custom", "1.0" do |s|
      s.files = %w[lib/ext_custom.rb]
      s.require_paths = %w[lib]
    end

    written_path = write_file spec.spec_file do |io|
      io.write spec.to_ruby_for_cache
    end
    spec.loaded_from = written_path

    # Set a custom extension_dir directly using the writer
    custom_ext = File.join(@tempdir, "custom_extensions", spec.full_name)
    spec.extension_dir = custom_ext
    assert_equal custom_ext, spec.extension_dir
    assert_equal File.join(custom_ext, "gem.build_complete"), spec.gem_build_complete_path
  end

  # Additional: full_gem_path with custom full_gem_path writer
  def test_full_gem_path_custom_writer
    spec = util_spec "custom_path", "1.0" do |s|
      s.files = %w[lib/custom_path.rb]
      s.require_paths = %w[lib]
    end

    custom_path = File.join(@tempdir, "custom_gems", "custom_path-1.0")
    spec.full_gem_path = custom_path
    assert_equal custom_path, spec.full_gem_path
    assert_kind_of String, spec.full_gem_path
  end

  # Additional: base_dir_priority method
  def test_base_dir_priority
    gem_path = [Gem.dir, File.join(@tempdir, "other")]
    priority = @spec.base_dir_priority(gem_path)
    assert_kind_of Integer, priority
    # base_dir should be found within gem_path or equal gem_path.size
    assert priority >= 0
  end

  # Additional: BasicSpecification this returns self on abstract instance
  def test_this_returns_self_abstract
    bs = Gem::BasicSpecification.new
    result = bs.this
    assert_same bs, result
    assert_equal bs.object_id, result.object_id
  end

  # Additional: default_gem? with nil loaded_from
  def test_default_gem_nil_loaded_from
    spec = util_spec "nil_loaded", "1.0"
    spec.loaded_from = nil
    assert_equal false, spec.default_gem?
    refute spec.default_gem?
  end
end
