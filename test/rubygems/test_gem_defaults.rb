# frozen_string_literal: true

require_relative "helper"

class TestGemDefaults < Gem::TestCase
  # Tests that the production Gem.default_sources method returns an array
  # containing the canonical RubyGems.org URL when no override is cached.
  def test_default_sources_contains_rubygems_org
    Gem.instance_variable_set(:@default_sources, nil)

    sources = Gem.default_sources

    assert_kind_of Array, sources
    assert_includes sources, "https://rubygems.org/"
  end

  # Tests that Gem.default_sources always returns a non-empty array,
  # even when using the test harness override value.
  def test_default_sources_non_empty
    sources = Gem.default_sources

    assert_kind_of Array, sources
    refute_empty sources
  end

  # Tests that the production Gem.default_dir computes a String path
  # derived from RbConfig that includes 'gems' as a path component.
  def test_default_dir_returns_string_path
    Gem.instance_variable_set(:@default_dir, nil)

    result = Gem.default_dir

    assert_kind_of String, result
    assert_includes result, "gems"
  end

  # Tests that Gem.default_spec_cache_dir returns a non-empty String
  # representing a filesystem path for cached specifications.
  def test_default_spec_cache_dir_returns_string
    result = Gem.default_spec_cache_dir

    assert_kind_of String, result
    refute_empty result
  end

  # Tests that Gem.default_specifications_dir returns a path containing
  # the 'specifications' and 'default' directory components.
  def test_default_specifications_dir_contains_default
    result = Gem.default_specifications_dir

    assert_kind_of String, result
    assert_match(%r{specifications.*default}, result)
  end

  # Tests that Gem.user_home returns a non-empty String representing
  # the user's home directory path.
  def test_user_home_returns_string
    result = Gem.user_home

    assert_kind_of String, result
    refute_empty result
  end

  # Tests that Gem.user_dir returns a String path that includes the
  # current Ruby engine identifier as a path component.
  def test_user_dir_contains_ruby_engine
    result = Gem.user_dir

    assert_kind_of String, result
    assert_includes result, Gem.ruby_engine
  end

  # Tests that Gem.config_home returns a non-empty String path for
  # the user's configuration home directory (XDG or fallback).
  def test_config_home_returns_string
    result = Gem.config_home

    assert_kind_of String, result
    refute_empty result
  end

  # Tests that Gem.data_home returns a non-empty String path for
  # the user's data home directory (XDG or fallback).
  def test_data_home_returns_string
    result = Gem.data_home

    assert_kind_of String, result
    refute_empty result
  end

  # Tests that Gem.state_home returns a non-empty String path for
  # the user's state home directory (XDG or fallback).
  def test_state_home_returns_string
    result = Gem.state_home

    assert_kind_of String, result
    refute_empty result
  end

  # Tests that Gem.cache_home returns a non-empty String path for
  # the user's cache home directory (XDG or fallback).
  def test_cache_home_returns_string
    result = Gem.cache_home

    assert_kind_of String, result
    refute_empty result
  end

  # Tests that Gem.default_path returns an Array that always includes
  # the Gem.default_dir value.
  def test_default_path_includes_default_dir
    path = Gem.default_path

    assert_kind_of Array, path
    assert_includes path, Gem.default_dir
  end

  # Tests that Gem.default_path includes the user_dir when the
  # user's home directory exists on the filesystem.
  def test_default_path_includes_user_dir
    assert File.exist?(Gem.user_home), "user_home must exist for this test"

    path = Gem.default_path

    assert_kind_of Array, path
    assert_includes path, Gem.user_dir
  end

  # Tests that Gem.default_bindir returns a non-empty String
  # representing the directory for binary executables.
  def test_default_bindir_returns_string
    result = Gem.default_bindir

    assert_kind_of String, result
    refute_empty result
  end

  # Tests that Gem.default_exec_format returns a format String
  # containing the '%s' placeholder for executable name substitution.
  def test_default_exec_format_includes_percent_s
    result = Gem.default_exec_format

    assert_kind_of String, result
    assert_includes result, "%s"
  end

  # Tests that Gem.default_key_path returns a path String ending
  # with the standard private key PEM filename.
  def test_default_key_path_ends_with_pem
    result = Gem.default_key_path

    assert_kind_of String, result
    assert_match(/gem-private_key\.pem\z/, result)
  end

  # Tests that Gem.default_cert_path returns a path String ending
  # with the standard public certificate PEM filename.
  def test_default_cert_path_ends_with_pem
    result = Gem.default_cert_path

    assert_kind_of String, result
    assert_match(/gem-public_cert\.pem\z/, result)
  end

  # Tests that Gem.path_separator returns a String equal to
  # the platform's File::PATH_SEPARATOR constant.
  def test_path_separator_equals_file_path_separator
    result = Gem.path_separator

    assert_kind_of String, result
    assert_equal File::PATH_SEPARATOR, result
  end

  # Tests that Gem.operating_system_defaults returns an empty Hash
  # in the default (non-overridden) configuration.
  def test_operating_system_defaults_returns_empty_hash
    result = Gem.operating_system_defaults

    assert_kind_of Hash, result
    assert_empty result
  end

  # Tests that Gem.platform_defaults returns an empty Hash
  # in the default (non-overridden) configuration.
  def test_platform_defaults_returns_empty_hash
    result = Gem.platform_defaults

    assert_kind_of Hash, result
    assert_empty result
  end

  # Tests that Gem.default_ext_dir_for returns nil for any base_dir
  # argument, indicating extensions are co-located with Ruby files.
  def test_default_ext_dir_for_returns_nil
    result = Gem.default_ext_dir_for(Gem.default_dir)

    assert_nil result

    result_with_arbitrary_path = Gem.default_ext_dir_for("/some/arbitrary/path")

    assert_nil result_with_arbitrary_path
  end

  # Tests that Gem.ruby_engine returns a String equal to the
  # RUBY_ENGINE constant for the current Ruby implementation.
  def test_ruby_engine_returns_ruby_engine
    result = Gem.ruby_engine

    assert_kind_of String, result
    assert_equal RUBY_ENGINE, result
  end

  # Tests that Gem.find_config_file returns a non-empty String path
  # for the user's gem configuration file location.
  def test_find_config_file_returns_string
    result = Gem.find_config_file

    assert_kind_of String, result
    refute_empty result
  end
end
