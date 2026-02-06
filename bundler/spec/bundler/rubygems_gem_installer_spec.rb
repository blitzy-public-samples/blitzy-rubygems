# frozen_string_literal: true

require "spec_helper"
require "bundler/rubygems_gem_installer"
require "tmpdir"

RSpec.describe Bundler::RubyGemsGemInstaller do
  let(:gem_name) { "test_gem" }
  let(:gem_version) { Gem::Version.new("1.0.0") }
  let(:tmp_dir) { @tmp_dir_path }
  let(:gem_home_dir) { tmp_dir }
  let(:gem_dir_path) { File.join(gem_home_dir, "gems", "#{gem_name}-#{gem_version}") }
  let(:spec_obj) do
    Gem::Specification.new do |s|
      s.name = gem_name
      s.version = gem_version
      s.summary = "A test gem"
      s.authors = ["Test Author"]
    end
  end
  let(:package) do
    pkg = double("Gem::Package",
      spec: spec_obj,
      dir_mode: nil,
      prog_mode: nil,
      data_mode: nil)
    allow(pkg).to receive(:dir_mode=)
    allow(pkg).to receive(:prog_mode=)
    allow(pkg).to receive(:data_mode=)
    pkg
  end
  let(:installer_options) { { install_dir: gem_home_dir } }

  subject { described_class.new(package, installer_options) }

  before do
    @tmp_dir_path = Dir.mktmpdir("rubygems_gem_installer_spec")
  end

  after do
    FileUtils.rm_rf(@tmp_dir_path) if @tmp_dir_path && File.exist?(@tmp_dir_path)
  end

  # ---------------------------------------------------------------------------
  # Class hierarchy verification
  # ---------------------------------------------------------------------------

  describe "class hierarchy" do
    it "inherits from Gem::Installer and is included in ancestors" do
      expect(described_class).to be < Gem::Installer
      expect(described_class.ancestors).to include(Gem::Installer)
    end

    it "is defined as a constant within the Bundler namespace" do
      expect(described_class.name).to eq("Bundler::RubyGemsGemInstaller")
      expect(defined?(Bundler::RubyGemsGemInstaller)).to eq("constant")
    end

    it "creates instances that satisfy both type checks" do
      expect(subject).to be_a(described_class)
      expect(subject).to be_a(Gem::Installer)
    end
  end

  # ---------------------------------------------------------------------------
  # #check_executable_overwrite — no-op override
  # ---------------------------------------------------------------------------

  describe "#check_executable_overwrite" do
    it "accepts a filename argument and returns nil" do
      result = subject.check_executable_overwrite("my_executable")
      expect(result).to be_nil
      expect(subject).to respond_to(:check_executable_overwrite)
    end

    it "does not raise for any filename value" do
      expect { subject.check_executable_overwrite("some_bin") }.not_to raise_error
      expect { subject.check_executable_overwrite("") }.not_to raise_error
    end

    it "is defined directly on the described class (overrides parent)" do
      owner = described_class.instance_method(:check_executable_overwrite).owner
      expect(owner).to eq(described_class)
      expect(subject.check_executable_overwrite("anything")).to be_nil
    end

    it "accepts filenames with special characters without error" do
      expect { subject.check_executable_overwrite("bin/my-tool.sh") }.not_to raise_error
      expect(subject.check_executable_overwrite("bin/my-tool.sh")).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # #install — full installation flow
  # ---------------------------------------------------------------------------

  describe "#install" do
    before do
      # Stub all inherited parent-class lifecycle hooks and I/O operations
      allow(subject).to receive(:pre_install_checks)
      allow(subject).to receive(:run_pre_install_hooks)
      allow(subject).to receive(:run_post_build_hooks)
      allow(subject).to receive(:run_post_install_hooks)
      allow(subject).to receive(:extract_files)
      allow(subject).to receive(:generate_bin)
      allow(subject).to receive(:write_spec)
      allow(subject).to receive(:write_cache_file)
      allow(subject).to receive(:write_build_info_file)
      allow(subject).to receive(:say)
      allow(subject).to receive(:spec_file).and_return(File.join(tmp_dir, "fake.gemspec"))

      # Stub external file system access to yield without real FS operations
      allow(Bundler::SharedHelpers).to receive(:filesystem_access).and_yield

      # Stub private method that removes previous installation directories
      allow(subject).to receive(:strict_rm_rf)

      # Stub generate_plugins (tested separately in its own describe block)
      allow(subject).to receive(:generate_plugins)

      # Configure spec to have no extensions by default
      allow(spec_obj).to receive(:extensions).and_return([])
      allow(spec_obj).to receive(:extension_dir).and_return(File.join(tmp_dir, "ext"))
      allow(spec_obj).to receive(:post_install_message).and_return(nil)

      # Stub FileUtils.mkdir_p for gem_dir creation within filesystem_access
      allow(FileUtils).to receive(:mkdir_p)
    end

    it "returns the spec object upon successful installation" do
      result = subject.install
      expect(result).to eq(spec_obj)
      expect(result.name).to eq(gem_name)
    end

    it "returns a spec with the correct version" do
      result = subject.install
      expect(result).to be_a(Gem::Specification)
      expect(result.version).to eq(gem_version)
    end

    it "invokes pre_install_checks during the install flow" do
      expect(subject).to receive(:pre_install_checks).once
      result = subject.install
      expect(result).to eq(spec_obj)
    end

    it "invokes lifecycle hooks in the correct sequential order" do
      call_order = []
      allow(subject).to receive(:pre_install_checks) { call_order << :pre_install_checks }
      allow(subject).to receive(:run_pre_install_hooks) { call_order << :run_pre_install_hooks }
      allow(subject).to receive(:write_build_info_file) { call_order << :write_build_info_file }
      allow(subject).to receive(:run_post_build_hooks) { call_order << :run_post_build_hooks }
      allow(subject).to receive(:run_post_install_hooks) { call_order << :run_post_install_hooks }

      subject.install

      expect(call_order).to eq([
        :pre_install_checks,
        :run_pre_install_hooks,
        :write_build_info_file,
        :run_post_build_hooks,
        :run_post_install_hooks,
      ])
      expect(call_order.length).to eq(5)
    end

    it "calls generate_plugins during the install flow" do
      expect(subject).to receive(:generate_plugins).once
      result = subject.install
      expect(result).to eq(spec_obj)
    end

    it "calls write_spec during the install flow" do
      expect(subject).to receive(:write_spec).once
      result = subject.install
      expect(result).to eq(spec_obj)
    end

    it "calls extract_files within a filesystem_access block" do
      expect(subject).to receive(:extract_files).once
      result = subject.install
      expect(result).to eq(spec_obj)
    end

    it "calls generate_bin within a filesystem_access block" do
      expect(subject).to receive(:generate_bin).once
      result = subject.install
      expect(result).to eq(spec_obj)
    end

    it "calls write_cache_file within a filesystem_access block" do
      expect(subject).to receive(:write_cache_file).once
      result = subject.install
      expect(result).to eq(spec_obj)
    end

    it "displays post_install_message when present" do
      allow(spec_obj).to receive(:post_install_message).and_return("Thank you for installing!")
      expect(subject).to receive(:say).with("Thank you for installing!")
      result = subject.install
      expect(result).to eq(spec_obj)
    end

    it "does not display post_install_message when nil" do
      allow(spec_obj).to receive(:post_install_message).and_return(nil)
      expect(subject).not_to receive(:say)
      result = subject.install
      expect(result).to eq(spec_obj)
    end

    it "does not call build_extensions when spec has no extensions" do
      allow(spec_obj).to receive(:extensions).and_return([])
      expect(subject).not_to receive(:build_extensions)
      result = subject.install
      expect(result).to eq(spec_obj)
    end

    it "calls build_extensions when spec has extensions" do
      allow(spec_obj).to receive(:extensions).and_return(["ext/test_gem/extconf.rb"])
      expect(subject).to receive(:build_extensions)
      result = subject.install
      expect(result).to eq(spec_obj)
    end

    it "removes previous gem directory and extension directory before install" do
      expect(subject).to receive(:strict_rm_rf).at_least(:twice)
      result = subject.install
      expect(result).to eq(spec_obj)
    end

    it "sets spec.loaded_from to spec_file path" do
      subject.install
      expect(spec_obj.loaded_from).to eq(File.join(tmp_dir, "fake.gemspec"))
      expect(spec_obj.loaded_from).to be_a(String)
    end
  end

  # ---------------------------------------------------------------------------
  # #ensure_writable_dir — permission error swallowing
  # ---------------------------------------------------------------------------

  describe "#ensure_writable_dir" do
    it "returns nil when parent raises Gem::FilePermissionError" do
      allow_any_instance_of(Gem::Installer).to receive(:ensure_writable_dir)
        .and_raise(Gem::FilePermissionError.new("/tmp/locked"))

      result = described_class.instance_method(:ensure_writable_dir).bind_call(subject, "/tmp/locked")
      expect(result).to be_nil
    end

    it "does not rescue non-permission errors from parent" do
      allow_any_instance_of(Gem::Installer).to receive(:ensure_writable_dir)
        .and_raise(RuntimeError.new("unexpected error"))

      expect do
        described_class.instance_method(:ensure_writable_dir).bind_call(subject, "/tmp/bad")
      end.to raise_error(RuntimeError, "unexpected error")
      expect(subject).to respond_to(:ensure_writable_dir)
    end
  end

  # ---------------------------------------------------------------------------
  # #generate_plugins — conditional plugin management
  # ---------------------------------------------------------------------------

  describe "#generate_plugins" do
    context "when Gem::Installer has generate_plugins defined" do
      before do
        allow(subject).to receive(:ensure_writable_dir)
      end

      it "skips processing when a newer version of the gem is already installed" do
        newer_stub = double("stub", version: Gem::Version.new("2.0.0"))
        allow(Gem::Specification).to receive(:stubs_for)
          .with(gem_name)
          .and_return([newer_stub])

        expect(subject).not_to receive(:ensure_writable_dir)
        subject.generate_plugins
      end

      it "calls regenerate_plugins_for when spec has plugins and is the latest version" do
        allow(Gem::Specification).to receive(:stubs_for)
          .with(gem_name)
          .and_return([])
        allow(spec_obj).to receive(:plugins).and_return(["my_plugin.rb"])

        expect(subject).to receive(:regenerate_plugins_for)
        subject.generate_plugins
      end

      it "calls remove_plugins_for when spec has no plugins and is the latest version" do
        allow(Gem::Specification).to receive(:stubs_for)
          .with(gem_name)
          .and_return([])
        allow(spec_obj).to receive(:plugins).and_return([])

        expect(subject).to receive(:remove_plugins_for)
        subject.generate_plugins
      end

      it "proceeds with plugin management when installed version is older" do
        older_stub = double("stub", version: Gem::Version.new("0.5.0"))
        allow(Gem::Specification).to receive(:stubs_for)
          .with(gem_name)
          .and_return([older_stub])
        allow(spec_obj).to receive(:plugins).and_return([])

        expect(subject).to receive(:ensure_writable_dir)
        expect(subject).to receive(:remove_plugins_for)
        subject.generate_plugins
      end

      it "proceeds when no stubs are found for the gem name" do
        allow(Gem::Specification).to receive(:stubs_for)
          .with(gem_name)
          .and_return([])
        allow(spec_obj).to receive(:plugins).and_return(["plugin.rb"])

        expect(subject).to receive(:ensure_writable_dir)
        expect(subject).to receive(:regenerate_plugins_for)
        subject.generate_plugins
      end
    end

    context "when Gem::Installer does not have generate_plugins" do
      it "returns early without performing any plugin operations" do
        allow(Gem::Installer).to receive(:instance_methods)
          .with(false)
          .and_return([:install])

        expect(Gem::Specification).not_to receive(:stubs_for)
        expect(subject).not_to receive(:ensure_writable_dir)
        subject.generate_plugins
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #build_extensions — extension building with optional caching
  # ---------------------------------------------------------------------------

  describe "#build_extensions" do
    let(:extension_dir) { File.join(tmp_dir, "extensions") }

    before do
      allow(spec_obj).to receive(:extension_dir).and_return(extension_dir)
    end

    context "when no extension cache path is provided" do
      it "prepares the extension directory and delegates to parent" do
        builder_double = double("builder", build_extensions: nil)
        allow(Gem::Ext::Builder).to receive(:new).and_return(builder_double)

        subject.build_extensions

        expect(Dir.exist?(extension_dir)).to be true
        expect(builder_double).to have_received(:build_extensions)
      end
    end

    context "when extension cache path is provided and build is complete" do
      let(:extension_cache_path) { Pathname.new(File.join(tmp_dir, "ext_cache")) }

      before do
        FileUtils.mkdir_p(extension_cache_path)
        FileUtils.touch(extension_cache_path.join("gem.build_complete"))
        FileUtils.touch(extension_cache_path.join("some_extension.so"))
      end

      it "copies from cache instead of rebuilding" do
        allow(subject).to receive(:options).and_return(
          subject.options.merge(bundler_extension_cache_path: extension_cache_path)
        )

        subject.build_extensions

        expect(Dir.exist?(extension_dir)).to be true
        expect(File.exist?(File.join(extension_dir, "gem.build_complete"))).to be true
      end

      it "copies all cached files to the extension directory" do
        allow(subject).to receive(:options).and_return(
          subject.options.merge(bundler_extension_cache_path: extension_cache_path)
        )

        subject.build_extensions

        expect(File.exist?(File.join(extension_dir, "some_extension.so"))).to be true
        expect(Dir.exist?(extension_dir)).to be true
      end
    end

    context "when extension cache path is provided but build is not complete" do
      let(:extension_cache_path) { Pathname.new(File.join(tmp_dir, "ext_cache_new")) }

      it "builds extensions and then caches the result" do
        builder_double = double("builder", build_extensions: nil)
        allow(Gem::Ext::Builder).to receive(:new).and_return(builder_double)

        allow(subject).to receive(:options).and_return(
          subject.options.merge(bundler_extension_cache_path: extension_cache_path)
        )

        # Pre-create the extension dir so cp_r has content to copy
        FileUtils.mkdir_p(extension_dir)
        FileUtils.touch(File.join(extension_dir, "built_ext.so"))

        subject.build_extensions

        expect(Dir.exist?(extension_cache_path.to_s)).to be true
        expect(builder_double).to have_received(:build_extensions)
      end
    end

    context "when force option is set and cache exists" do
      let(:extension_cache_path) { Pathname.new(File.join(tmp_dir, "ext_cache_force")) }

      before do
        FileUtils.mkdir_p(extension_cache_path)
        FileUtils.touch(extension_cache_path.join("gem.build_complete"))
      end

      it "rebuilds extensions despite existing cache" do
        builder_double = double("builder", build_extensions: nil)
        allow(Gem::Ext::Builder).to receive(:new).and_return(builder_double)

        allow(subject).to receive(:options).and_return(
          subject.options.merge(
            bundler_extension_cache_path: extension_cache_path,
            force: true
          )
        )

        FileUtils.mkdir_p(extension_dir)
        FileUtils.touch(File.join(extension_dir, "rebuilt_ext.so"))

        subject.build_extensions

        expect(builder_double).to have_received(:build_extensions)
        expect(Dir.exist?(extension_cache_path.to_s)).to be true
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #spec — specification accessor
  # ---------------------------------------------------------------------------

  describe "#spec" do
    it "returns the gem specification from the package" do
      result = subject.spec
      expect(result).to be_a(Gem::Specification)
      expect(result.name).to eq(gem_name)
    end

    it "returns consistent spec values across multiple calls" do
      first_call = subject.spec
      second_call = subject.spec
      expect(first_call.name).to eq(second_call.name)
      expect(first_call.version).to eq(second_call.version)
    end
  end

  # ---------------------------------------------------------------------------
  # #gem_checksum — delegates to Bundler::Checksum
  # ---------------------------------------------------------------------------

  describe "#gem_checksum" do
    it "delegates to Bundler::Checksum.from_gem_package with the package" do
      checksum_result = double("checksum")
      expect(Bundler::Checksum).to receive(:from_gem_package)
        .with(package)
        .and_return(checksum_result)

      result = subject.gem_checksum
      expect(result).to eq(checksum_result)
    end

    it "passes the same package instance provided at construction" do
      allow(Bundler::Checksum).to receive(:from_gem_package).and_return(nil)

      subject.gem_checksum

      expect(Bundler::Checksum).to have_received(:from_gem_package).with(package)
      expect(subject).to respond_to(:gem_checksum)
    end
  end

  # ---------------------------------------------------------------------------
  # Instance construction
  # ---------------------------------------------------------------------------

  describe "instance construction" do
    it "can be instantiated with a package and options" do
      inst = described_class.new(package, installer_options)
      expect(inst).to be_a(described_class)
      expect(inst).to be_a(Gem::Installer)
    end

    it "stores the options passed during initialization" do
      inst = described_class.new(package, installer_options)
      expect(inst.options).to include(:install_dir)
      expect(inst.options[:install_dir]).to eq(gem_home_dir)
    end
  end

  # ---------------------------------------------------------------------------
  # Build arguments — pass-through to extension building
  # ---------------------------------------------------------------------------

  context "build arguments" do
    let(:build_args) { ["--with-opt-dir=/usr/local", "--enable-debug"] }
    let(:installer_with_build_args) do
      described_class.new(package, installer_options.merge(build_args: build_args))
    end

    it "stores build args from options for use during extension building" do
      result = installer_with_build_args.send(:build_args)
      expect(result).to eq(build_args)
      expect(result.length).to eq(2)
    end

    it "passes build args to Gem::Ext::Builder when building extensions" do
      allow(spec_obj).to receive(:extension_dir).and_return(File.join(tmp_dir, "ext_ba"))

      builder_double = double("builder", build_extensions: nil)
      received_args = nil
      allow(Gem::Ext::Builder).to receive(:new) do |spec_arg, args_arg, *_rest|
        received_args = args_arg
        builder_double
      end

      installer_with_build_args.build_extensions
      expect(received_args).to eq(build_args)
      expect(builder_double).to have_received(:build_extensions)
    end

    it "defaults build_args when not explicitly provided in options" do
      # When build_args is not provided, it falls back to Gem::Command.build_args
      inst = described_class.new(package, installer_options)
      result = inst.send(:build_args)
      expect(result).to be_a(Array)
      expect(result).to respond_to(:each)
    end
  end

  # ---------------------------------------------------------------------------
  # Extension compilation — behavior with non-empty vs empty extensions
  # ---------------------------------------------------------------------------

  context "extension compilation" do
    before do
      # Stub all inherited parent-class lifecycle hooks and I/O operations
      allow(subject).to receive(:pre_install_checks)
      allow(subject).to receive(:run_pre_install_hooks)
      allow(subject).to receive(:run_post_build_hooks)
      allow(subject).to receive(:run_post_install_hooks)
      allow(subject).to receive(:extract_files)
      allow(subject).to receive(:generate_bin)
      allow(subject).to receive(:write_spec)
      allow(subject).to receive(:write_cache_file)
      allow(subject).to receive(:write_build_info_file)
      allow(subject).to receive(:say)
      allow(subject).to receive(:spec_file).and_return(File.join(tmp_dir, "fake.gemspec"))
      allow(Bundler::SharedHelpers).to receive(:filesystem_access).and_yield
      allow(subject).to receive(:strict_rm_rf)
      allow(subject).to receive(:generate_plugins)
      allow(spec_obj).to receive(:post_install_message).and_return(nil)
      allow(FileUtils).to receive(:mkdir_p)
    end

    context "when spec.extensions is non-empty" do
      before do
        allow(spec_obj).to receive(:extensions).and_return(["ext/test_gem/extconf.rb"])
        allow(spec_obj).to receive(:extension_dir).and_return(File.join(tmp_dir, "ext_comp"))
      end

      it "triggers build_extensions during the install flow" do
        builder_double = double("builder", build_extensions: nil)
        allow(Gem::Ext::Builder).to receive(:new).and_return(builder_double)

        result = subject.install
        expect(result).to eq(spec_obj)
        expect(builder_double).to have_received(:build_extensions)
      end

      it "invokes the extension builder and returns the spec" do
        builder_double = double("builder", build_extensions: nil)
        allow(Gem::Ext::Builder).to receive(:new).and_return(builder_double)

        result = subject.install
        expect(result.name).to eq(gem_name)
        expect(result.version).to eq(gem_version)
      end
    end

    context "when spec.extensions is empty" do
      before do
        allow(spec_obj).to receive(:extensions).and_return([])
        allow(spec_obj).to receive(:extension_dir).and_return(File.join(tmp_dir, "ext_empty"))
      end

      it "does not trigger build_extensions during install" do
        expect(Gem::Ext::Builder).not_to receive(:new)
        result = subject.install
        expect(result).to eq(spec_obj)
      end

      it "completes the installation without extension-related operations" do
        result = subject.install
        expect(result.name).to eq(gem_name)
        expect(result.version).to eq(gem_version)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Public method interface — responds to all overridden methods
  # ---------------------------------------------------------------------------

  describe "public method interface" do
    it "responds to all overridden public methods from production class" do
      expect(subject).to respond_to(:check_executable_overwrite)
      expect(subject).to respond_to(:install)
      expect(subject).to respond_to(:ensure_writable_dir)
      expect(subject).to respond_to(:generate_plugins)
      expect(subject).to respond_to(:build_extensions)
      expect(subject).to respond_to(:spec)
      expect(subject).to respond_to(:gem_checksum)
    end

    it "defines check_executable_overwrite and install on the class itself" do
      expect(described_class.instance_method(:check_executable_overwrite).owner).to eq(described_class)
      expect(described_class.instance_method(:install).owner).to eq(described_class)
    end

    it "defines build_extensions and generate_plugins on the class itself" do
      expect(described_class.instance_method(:build_extensions).owner).to eq(described_class)
      expect(described_class.instance_method(:generate_plugins).owner).to eq(described_class)
    end
  end
end
