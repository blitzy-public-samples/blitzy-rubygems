# frozen_string_literal: true

require_relative "helper"
require "rubygems/installer_uninstaller_utils"

class TestGemInstallerUninstallerUtils < Gem::TestCase
  # Include the module under test so we can invoke its methods directly.
  # The module expects a `verbose` method to be available on the receiver,
  # which is normally provided by Gem::Installer. We provide a no-op here.
  include Gem::InstallerUninstallerUtils

  def verbose(msg)
    # no-op for test — suppresses installer verbosity output
  end

  def setup
    super
    @plugins_dir = File.join(@tempdir, "test_plugins")
    FileUtils.mkdir_p @plugins_dir
  end

  ##
  # Test that regenerate_plugins_for creates a plugin wrapper script
  # in the plugins directory for a spec that has a plugin file on disk.

  def test_regenerate_plugins_for
    spec = quick_gem "myplugin_gem" do |s|
      s.files = %w[lib/rubygems_plugin.rb]
    end

    # Create the actual plugin source file on disk inside the gem's lib dir
    plugin_source = File.join(spec.gem_dir, "lib", "rubygems_plugin.rb")
    FileUtils.mkdir_p File.dirname(plugin_source)
    File.open(plugin_source, "w") { |f| f.write "# myplugin_gem plugin" }

    regenerate_plugins_for(spec, @plugins_dir)

    plugin_path = File.join(@plugins_dir, "myplugin_gem_plugin.rb")

    assert File.exist?(plugin_path), "Expected plugin wrapper to be created at #{plugin_path}"
    assert_match(/require_relative/, File.read(plugin_path))
  end

  ##
  # Test that regenerate_plugins_for does nothing when the spec has no plugins
  # (i.e., no rubygems_plugin files exist on disk).

  def test_regenerate_plugins_for_empty_plugins
    spec = quick_gem "noplugin_gem"

    # Do NOT create any rubygems_plugin.rb file on disk — spec.plugins returns []
    regenerate_plugins_for(spec, @plugins_dir)

    plugin_files = Dir.glob(File.join(@plugins_dir, "*_plugin*"))

    assert_empty plugin_files, "No plugin files should be created when spec has no plugins"
    refute File.exist?(File.join(@plugins_dir, "noplugin_gem_plugin.rb"))
  end

  ##
  # Test that remove_plugins_for deletes plugin wrapper scripts matching
  # the spec name from the plugins directory.

  def test_remove_plugins_for
    spec = quick_gem "removable_gem"

    # Pre-create a plugin wrapper file that matches the expected naming pattern
    plugin_path = File.join(@plugins_dir, "removable_gem_plugin.rb")
    File.open(plugin_path, "w") { |f| f.write "require_relative 'some/path'" }

    assert File.exist?(plugin_path), "Plugin file should exist before removal"

    remove_plugins_for(spec, @plugins_dir)

    refute File.exist?(plugin_path), "Plugin file should be removed after remove_plugins_for"
    assert_empty Dir.glob(File.join(@plugins_dir, "removable_gem*")),
      "No files matching the gem name should remain in plugins dir"
  end

  ##
  # Test that regenerate_plugins_for writes a require_relative statement
  # pointing back to the actual plugin source file.

  def test_regenerate_plugins_for_creates_require_relative
    spec = quick_gem "writer_gem" do |s|
      s.files = %w[lib/rubygems_plugin.rb]
    end

    # Create the plugin source file on disk so spec.plugins finds it
    plugin_source = File.join(spec.gem_dir, "lib", "rubygems_plugin.rb")
    FileUtils.mkdir_p File.dirname(plugin_source)
    File.open(plugin_source, "w") { |f| f.write "# writer_gem plugin content" }

    regenerate_plugins_for(spec, @plugins_dir)

    generated_path = File.join(@plugins_dir, "writer_gem_plugin.rb")
    content = File.read(generated_path)

    assert_match(/require_relative/, content)
    assert_kind_of String, content
  end
end
