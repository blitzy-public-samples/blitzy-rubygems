# frozen_string_literal: true

require "tmpdir"
require "bundler/rubygems_gem_installer"

RSpec.describe Bundler::RubyGemsGemInstaller do
  let(:gem_name) { "test_gem" }
  let(:gem_version) { Gem::Version.new("1.0.0") }
  let(:tmp_dir) { @tmp_dir_path }
  let(:gem_home) { tmp_dir }
  let(:gem_dir) { File.join(gem_home, "gems", "#{gem_name}-#{gem_version}") }
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
  let(:installer_options) { { install_dir: gem_home } }

  subject do
    described_class.new(package, installer_options)
  end

  before do
    @tmp_dir_path = Dir.mktmpdir("rubygems_gem_installer_spec")
  end

  after do
    FileUtils.rm_rf(@tmp_dir_path) if @tmp_dir_path && File.exist?(@tmp_dir_path)
  end

  describe "class hierarchy" do
    it "inherits from Gem::Installer" do
      expect(described_class).to be < Gem::Installer
      expect(described_class.ancestors).to include(Gem::Installer)
    end

    it "is defined within the Bundler namespace" do
      expect(described_class.name).to eq("Bundler::RubyGemsGemInstaller")
      expect(defined?(Bundler::RubyGemsGemInstaller)).to eq("constant")
    end
  end

  describe "#check_executable_overwrite" do
    it "accepts a filename argument and does nothing" do
      result = subject.check_executable_overwrite("my_executable")
      expect(result).to be_nil
    end

    it "does not raise an error for any filename" do
      expect { subject.check_executable_overwrite("some_bin") }.not_to raise_error
      expect { subject.check_executable_overwrite("") }.not_to raise_error
    end

    it "overrides the parent class method" do
      expect(described_class.instance_method(:check_executable_overwrite).owner).to eq(described_class)
      expect(subject).to respond_to(:check_executable_overwrite)
    end
  end

  describe "#install" do
    before do
      # Stub all external/inherited methods that perform I/O operations.
      # These are parent-class lifecycle hooks and file system operations
      # that are outside the scope of what we are testing.
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

      # Stub filesystem access to yield immediately without real FS ops
      allow(Bundler::SharedHelpers).to receive(:filesystem_access).and_yield

      # Stub private strict_rm_rf used in install to remove old dirs
      allow(subject).to receive(:strict_rm_rf)

      # Stub generate_plugins (tested separately)
      allow(subject).to receive(:generate_plugins)

      # Configure spec to have no extensions by default
      allow(spec_obj).to receive(:extensions).and_return([])
      allow(spec_obj).to receive(:extension_dir).and_return(File.join(tmp_dir, "ext"))
      allow(spec_obj).to receive(:post_install_message).and_return(nil)

      # Stub FileUtils.mkdir_p for gem_dir creation
      allow(FileUtils).to receive(:mkdir_p)
    end

    it "returns the spec object upon successful installation" do
      result = subject.install
      expect(result).to eq(spec_obj)
      expect(result.name).to eq(gem_name)
    end

    it "invokes pre_install_checks during the install flow" do
      expect(subject).to receive(:pre_install_checks).once
      subject.install
    end

    it "invokes lifecycle hooks in the correct order" do
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
    end

    it "calls generate_plugins during the install flow" do
      expect(subject).to receive(:generate_plugins).once
      subject.install
    end

    it "calls write_spec during the install flow" do
      expect(subject).to receive(:write_spec).once
      subject.install
    end

    it "displays post_install_message when present" do
      allow(spec_obj).to receive(:post_install_message).and_return("Thank you for installing!")
      expect(subject).to receive(:say).with("Thank you for installing!")
      subject.install
    end

    it "does not display post_install_message when nil" do
      allow(spec_obj).to receive(:post_install_message).and_return(nil)
      expect(subject).not_to receive(:say)
      subject.install
    end

    it "does not call build_extensions when spec has no extensions" do
      allow(spec_obj).to receive(:extensions).and_return([])
      expect(subject).not_to receive(:build_extensions)
      subject.install
    end
  end

  describe "#ensure_writable_dir" do
    it "returns nil when parent raises Gem::FilePermissionError" do
      # Force the super call to raise the permission error
      allow(subject).to receive(:ensure_writable_dir).and_call_original
      allow_any_instance_of(Gem::Installer).to receive(:ensure_writable_dir)
        .and_raise(Gem::FilePermissionError.new("/tmp/locked"))

      # Call the actual method on subject
      result = described_class.instance_method(:ensure_writable_dir).bind_call(subject, "/tmp/locked")
      expect(result).to be_nil
    end

    it "does not rescue non-permission errors from parent" do
      allow_any_instance_of(Gem::Installer).to receive(:ensure_writable_dir)
        .and_raise(RuntimeError.new("unexpected"))

      expect do
        described_class.instance_method(:ensure_writable_dir).bind_call(subject, "/tmp/bad")
      end.to raise_error(RuntimeError, "unexpected")
    end
  end

  describe "#generate_plugins" do
    context "when Gem::Installer has generate_plugins defined" do
      before do
        # The production code checks Gem::Installer.instance_methods(false)
        # which returns the methods defined directly on Gem::Installer.
        # In our environment, generate_plugins IS defined on Gem::Installer,
        # so the guard passes naturally.
        allow(subject).to receive(:ensure_writable_dir)
      end

      it "skips when a newer version is already installed" do
        newer_stub = double("stub", version: Gem::Version.new("2.0.0"))
        allow(Gem::Specification).to receive(:stubs_for)
          .with(gem_name)
          .and_return([newer_stub])

        # Should return early — never calls ensure_writable_dir
        expect(subject).not_to receive(:ensure_writable_dir)
        subject.generate_plugins
      end

      it "calls regenerate_plugins_for when spec has plugins and this is latest version" do
        allow(Gem::Specification).to receive(:stubs_for)
          .with(gem_name)
          .and_return([])
        allow(spec_obj).to receive(:plugins).and_return(["my_plugin.rb"])
        expect(subject).to receive(:regenerate_plugins_for)
        subject.generate_plugins
      end

      it "calls remove_plugins_for when spec has no plugins and this is latest version" do
        allow(Gem::Specification).to receive(:stubs_for)
          .with(gem_name)
          .and_return([])
        allow(spec_obj).to receive(:plugins).and_return([])
        expect(subject).to receive(:remove_plugins_for)
        subject.generate_plugins
      end

      it "proceeds when installed version is older than current spec version" do
        older_stub = double("stub", version: Gem::Version.new("0.5.0"))
        allow(Gem::Specification).to receive(:stubs_for)
          .with(gem_name)
          .and_return([older_stub])
        allow(spec_obj).to receive(:plugins).and_return([])
        expect(subject).to receive(:remove_plugins_for)
        subject.generate_plugins
      end
    end

    context "when Gem::Installer does not have generate_plugins" do
      it "returns early without doing anything" do
        # Temporarily override the check to simulate absence
        allow(Gem::Installer).to receive(:instance_methods)
          .with(false)
          .and_return([:install])

        expect(Gem::Specification).not_to receive(:stubs_for)
        subject.generate_plugins
      end
    end
  end

  describe "#build_extensions" do
    let(:extension_dir) { File.join(tmp_dir, "extensions") }

    before do
      allow(spec_obj).to receive(:extension_dir).and_return(extension_dir)
    end

    context "when no extension cache path is provided" do
      it "prepares the extension directory and delegates to parent" do
        # Stub Gem::Ext::Builder to prevent real extension building via super
        builder_double = double("builder", build_extensions: nil)
        allow(Gem::Ext::Builder).to receive(:new).and_return(builder_double)

        subject.build_extensions

        # Verify that prepare_extension_build created the extension directory
        expect(Dir.exist?(extension_dir)).to be true
      end
    end

    context "when extension cache path is provided and build is complete" do
      let(:extension_cache_path) { Pathname.new(File.join(tmp_dir, "ext_cache")) }

      before do
        # Set up a real extension cache with a gem.build_complete marker
        FileUtils.mkdir_p(extension_cache_path)
        FileUtils.touch(extension_cache_path.join("gem.build_complete"))
        FileUtils.touch(extension_cache_path.join("some_extension.so"))
      end

      it "copies from cache instead of rebuilding" do
        allow(subject).to receive(:options).and_return(
          subject.options.merge(bundler_extension_cache_path: extension_cache_path)
        )

        subject.build_extensions

        # Verify files were copied from cache to extension_dir
        expect(Dir.exist?(extension_dir)).to be true
        expect(File.exist?(File.join(extension_dir, "gem.build_complete"))).to be true
        expect(File.exist?(File.join(extension_dir, "some_extension.so"))).to be true
      end
    end

    context "when extension cache path is provided but build is not complete" do
      let(:extension_cache_path) { Pathname.new(File.join(tmp_dir, "ext_cache")) }

      it "builds extensions and caches the result" do
        # Stub Gem::Ext::Builder to prevent real extension building via super
        builder_double = double("builder", build_extensions: nil)
        allow(Gem::Ext::Builder).to receive(:new).and_return(builder_double)

        allow(subject).to receive(:options).and_return(
          subject.options.merge(bundler_extension_cache_path: extension_cache_path)
        )

        # Pre-create the extension dir so cp_r has something to copy
        FileUtils.mkdir_p(extension_dir)
        FileUtils.touch(File.join(extension_dir, "built_ext.so"))

        subject.build_extensions

        # Verify the extension dir contents were copied to cache
        expect(Dir.exist?(extension_cache_path.to_s)).to be true
      end
    end
  end

  describe "#spec" do
    it "returns the gem specification from the package" do
      result = subject.spec
      expect(result).to be_a(Gem::Specification)
      expect(result.name).to eq(gem_name)
    end

    it "returns consistent spec across multiple calls" do
      first_call = subject.spec
      second_call = subject.spec
      expect(first_call.name).to eq(second_call.name)
      expect(first_call.version).to eq(second_call.version)
    end
  end

  describe "#gem_checksum" do
    it "delegates to Bundler::Checksum.from_gem_package" do
      checksum_result = double("checksum")
      expect(Bundler::Checksum).to receive(:from_gem_package)
        .with(package)
        .and_return(checksum_result)

      result = subject.gem_checksum
      expect(result).to eq(checksum_result)
    end
  end

  describe "instance construction" do
    it "can be instantiated with a package and options" do
      inst = described_class.new(package, installer_options)
      expect(inst).to be_a(described_class)
      expect(inst).to be_a(Gem::Installer)
    end

    it "stores the options passed during initialization" do
      inst = described_class.new(package, installer_options)
      expect(inst.options).to include(:install_dir)
      expect(inst.options[:install_dir]).to eq(gem_home)
    end
  end

  describe "public method interface" do
    it "responds to all overridden public methods" do
      expect(subject).to respond_to(:check_executable_overwrite)
      expect(subject).to respond_to(:install)
      expect(subject).to respond_to(:ensure_writable_dir)
      expect(subject).to respond_to(:generate_plugins)
      expect(subject).to respond_to(:build_extensions)
      expect(subject).to respond_to(:spec)
      expect(subject).to respond_to(:gem_checksum)
    end

    it "defines check_executable_overwrite on the class itself" do
      owner = described_class.instance_method(:check_executable_overwrite).owner
      expect(owner).to eq(described_class)
    end

    it "defines install on the class itself" do
      owner = described_class.instance_method(:install).owner
      expect(owner).to eq(described_class)
    end

    it "defines build_extensions on the class itself" do
      owner = described_class.instance_method(:build_extensions).owner
      expect(owner).to eq(described_class)
    end
  end
end
