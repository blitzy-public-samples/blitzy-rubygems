# frozen_string_literal: true

require_relative "helper"
require "rubygems/target_rbconfig"

class TestGemTargetRbConfig < Gem::TestCase
  # Verifies .for_running_ruby returns a TargetRbConfig wrapping the
  # running Ruby's RbConfig with a nil path.
  def test_for_running_ruby
    config = Gem::TargetRbConfig.for_running_ruby

    assert_kind_of Gem::TargetRbConfig, config
    assert_nil config.path
  end

  # Verifies [] accessor delegates to the underlying RbConfig::CONFIG hash,
  # returning the same values as RbConfig::CONFIG for known keys.
  def test_bracket_accessor
    config = Gem::TargetRbConfig.for_running_ruby

    assert_equal RbConfig::CONFIG["host_os"], config["host_os"]
    assert_equal RbConfig::CONFIG["RUBY_INSTALL_NAME"], config["RUBY_INSTALL_NAME"]
  end

  # Verifies the path attribute reader returns the path provided at
  # initialization and that the accessor is available.
  def test_path_attribute
    config = Gem::TargetRbConfig.new(RbConfig, "/some/path")

    assert_respond_to config, :path
    assert_equal "/some/path", config.path
  end

  # Verifies .new creates a TargetRbConfig instance when given an rbconfig
  # module and nil path.
  def test_initialize
    config = Gem::TargetRbConfig.new(RbConfig, nil)

    assert_kind_of Gem::TargetRbConfig, config
    assert_nil config.path
  end

  # Verifies [] accessor returns String values for standard config keys
  # such as "arch" and "ruby_version".
  def test_bracket_returns_config_values
    config = Gem::TargetRbConfig.for_running_ruby

    assert_kind_of String, config["arch"]
    assert_kind_of String, config["ruby_version"]
  end

  # Verifies .from_path loads an rbconfig file from disk and creates a
  # TargetRbConfig that returns values from the loaded config, with the
  # path attribute set to the file path.
  def test_from_path_with_valid_rbconfig
    rbconfig_path = File.join(@tempdir, "fake_rbconfig.rb")

    File.write(rbconfig_path, <<~RUBY)
      module RbConfig
        CONFIG = {
          "host_os" => "test_os",
          "arch" => "test_arch",
          "ruby_version" => "9.9.9",
        }
      end
    RUBY

    config = Gem::TargetRbConfig.from_path(rbconfig_path)

    assert_kind_of Gem::TargetRbConfig, config
    assert_equal rbconfig_path, config.path
    assert_equal "test_os", config["host_os"]
    assert_equal "test_arch", config["arch"]
  end
end
