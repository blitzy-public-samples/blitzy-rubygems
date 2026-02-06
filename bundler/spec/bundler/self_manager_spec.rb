# frozen_string_literal: true

require "spec_helper"
require "bundler/self_manager"

RSpec.describe Bundler::SelfManager do
  subject(:self_manager) { described_class.new }

  # ---------------------------------------------------------------------------
  # Public method: #restart_with_locked_bundler_if_needed
  # Checks for a restart version via find_restart_version, verifies it is
  # installed, and invokes restart_with if both conditions are met.
  # ---------------------------------------------------------------------------
  describe "#restart_with_locked_bundler_if_needed" do
    context "when not in a bundle (find_restart_version returns nil)" do
      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(false)
      end

      it "returns nil without attempting any restart" do
        result = self_manager.restart_with_locked_bundler_if_needed
        expect(result).to be_nil
        expect(Bundler::SharedHelpers).to have_received(:in_bundle?)
      end
    end

    context "when configured version is 'system'" do
      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("system")
      end

      it "returns nil because system version bypasses restart logic" do
        result = self_manager.restart_with_locked_bundler_if_needed
        expect(result).to be_nil
        expect(Bundler.settings).to have_received(:[]).with(:version)
      end
    end

    context "when restart version is found but not installed" do
      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))
        allow(Bundler).to receive(:configure)
        allow(Bundler.rubygems).to receive(:find_bundler).with("2.4.0").and_return(nil)
        # ruby_can_restart_with_same_arguments? accesses $PROGRAM_NAME global state
        allow(self_manager).to receive(:ruby_can_restart_with_same_arguments?).and_return(true)
      end

      it "returns nil after checking that the version is not installed" do
        result = self_manager.restart_with_locked_bundler_if_needed
        expect(result).to be_nil
        expect(Bundler.rubygems).to have_received(:find_bundler).with("2.4.0")
      end
    end

    context "when restart version is found and installed" do
      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))
        allow(Bundler).to receive(:configure)
        allow(Bundler.rubygems).to receive(:find_bundler).with("2.4.0").and_return(true)
        allow(self_manager).to receive(:ruby_can_restart_with_same_arguments?).and_return(true)
        # External process control: mock Kernel.exec to prevent actual process replacement
        allow(Bundler).to receive(:with_original_env).and_yield
        allow(Kernel).to receive(:exec)
      end

      it "invokes Kernel.exec within original env with BUNDLER_VERSION set to the restart version" do
        self_manager.restart_with_locked_bundler_if_needed
        expect(Kernel).to have_received(:exec).with(
          hash_including("BUNDLER_VERSION" => "2.4.0"),
          any_args
        )
        expect(Bundler).to have_received(:with_original_env)
      end
    end

    context "when BUNDLER_VERSION environment variable is already set" do
      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))
      end

      it "returns nil because autoswitching does not apply when BUNDLER_VERSION is set" do
        original_bundler_version = ENV["BUNDLER_VERSION"]
        begin
          ENV["BUNDLER_VERSION"] = "2.3.0"
          result = self_manager.restart_with_locked_bundler_if_needed
          expect(result).to be_nil
          expect(Bundler::SharedHelpers).to have_received(:in_bundle?)
        ensure
          ENV["BUNDLER_VERSION"] = original_bundler_version
        end
      end
    end

    context "when currently running the same version as the lockfile" do
      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.4.0"))
        allow(self_manager).to receive(:ruby_can_restart_with_same_arguments?).and_return(true)
      end

      it "returns nil because no version switch is needed" do
        result = self_manager.restart_with_locked_bundler_if_needed
        expect(result).to be_nil
        expect(Bundler).to have_received(:gem_version)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Public method: #install_locked_bundler_and_restart_with_it_if_needed
  # Determines restart version, prints an info message indicating either
  # lockfile or configuration version, then delegates to install_and_restart_with.
  # ---------------------------------------------------------------------------
  describe "#install_locked_bundler_and_restart_with_it_if_needed" do
    context "when find_restart_version returns nil (not in bundle)" do
      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(false)
        allow(Bundler.ui).to receive(:info)
      end

      it "returns nil without displaying any info messages" do
        result = self_manager.install_locked_bundler_and_restart_with_it_if_needed
        expect(result).to be_nil
        expect(Bundler.ui).not_to have_received(:info)
      end
    end

    context "when restart version equals lockfile version" do
      let(:lockfile_ver) { "2.4.0" }

      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return(lockfile_ver)
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))
        allow(Bundler).to receive(:configure)
        allow(self_manager).to receive(:ruby_can_restart_with_same_arguments?).and_return(true)
        # install_and_restart_with is a private helper that accesses external state
        # (network for spec lookup, file system for installation, Kernel.exec for restart)
        allow(self_manager).to receive(:install_and_restart_with)
      end

      it "prints lockfile version info message and calls install_and_restart_with" do
        expect(Bundler.ui).to receive(:info).with(
          a_string_including("your lockfile was generated with #{lockfile_ver}")
        )
        self_manager.install_locked_bundler_and_restart_with_it_if_needed
        expect(self_manager).to have_received(:install_and_restart_with).with(Gem::Version.new(lockfile_ver))
      end
    end

    context "when restart version differs from lockfile version (explicit configured version)" do
      let(:configured_version) { "2.5.0" }

      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return(configured_version)
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))
        allow(Bundler).to receive(:configure)
        allow(self_manager).to receive(:ruby_can_restart_with_same_arguments?).and_return(true)
        allow(self_manager).to receive(:install_and_restart_with)
      end

      it "prints configuration version info message and calls install_and_restart_with" do
        expect(Bundler.ui).to receive(:info).with(
          a_string_including("your configuration was #{configured_version}")
        )
        self_manager.install_locked_bundler_and_restart_with_it_if_needed
        expect(self_manager).to have_received(:install_and_restart_with).with(Gem::Version.new(configured_version))
      end
    end

    context "when configured version is 'system'" do
      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("system")
        allow(Bundler.ui).to receive(:info)
      end

      it "returns nil without attempting install or printing messages" do
        result = self_manager.install_locked_bundler_and_restart_with_it_if_needed
        expect(result).to be_nil
        expect(Bundler.ui).not_to have_received(:info)
      end
    end

    context "when lockfile version is a dev version" do
      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.5.0.dev")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.4.0"))
        allow(self_manager).to receive(:ruby_can_restart_with_same_arguments?).and_return(true)
        allow(Bundler.ui).to receive(:info)
      end

      it "returns nil because dev versions are not considered released" do
        result = self_manager.install_locked_bundler_and_restart_with_it_if_needed
        expect(result).to be_nil
        expect(Bundler.ui).not_to have_received(:info)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Public method: #update_bundler_and_restart_with_it_if_needed(target)
  # Resolves an update version from a target requirement, installs if needed,
  # and restarts with the new version.
  # ---------------------------------------------------------------------------
  describe "#update_bundler_and_restart_with_it_if_needed" do
    context "when already running the target version (no update needed)" do
      let(:current_ver) { Gem::Version.new("2.5.0") }
      let(:mock_spec) do
        spec = double("spec", version: current_ver, name: "bundler")
        allow(spec).to receive(:source).and_return(double("source"))
        allow(spec).to receive(:<=>).and_return(0)
        spec
      end

      before do
        allow(Bundler).to receive(:gem_version).and_return(current_ver)
        allow(Bundler).to receive(:configure)
        allow(Bundler.ui).to receive(:info)

        local_source = double("local_source")
        allow(local_source).to receive(:specs).and_return(double(select: [mock_spec]))
        allow(Bundler::Source::Rubygems).to receive(:new).with("allow_local" => true).and_return(local_source)
      end

      it "returns nil without printing any update message" do
        result = self_manager.update_bundler_and_restart_with_it_if_needed("2.5.0")
        expect(result).to be_nil
        expect(Bundler.ui).not_to have_received(:info)
      end
    end

    context "when a newer version is found and not yet installed" do
      let(:current_ver) { Gem::Version.new("2.4.0") }
      let(:target_ver) { Gem::Version.new("2.5.0") }
      let(:mock_source) { double("source") }
      let(:mock_spec) do
        spec = double("spec", version: target_ver, name: "bundler", source: mock_source)
        allow(spec).to receive(:<=>).and_return(0)
        spec
      end

      before do
        allow(Bundler).to receive(:gem_version).and_return(current_ver)
        allow(Bundler).to receive(:configure)

        local_source = double("local_source")
        allow(local_source).to receive(:specs).and_return(double(select: [mock_spec]))
        allow(Bundler::Source::Rubygems).to receive(:new).with("allow_local" => true).and_return(local_source)

        # installed? returns nil → triggers install
        allow(Bundler.rubygems).to receive(:find_bundler).with(target_ver.to_s).and_return(nil)
        allow(mock_source).to receive(:install).with(mock_spec)
        allow(Bundler).to receive(:with_original_env).and_yield
        allow(Kernel).to receive(:exec)
        allow(Bundler.ui).to receive(:info)
      end

      it "prints the updating message and installs the spec" do
        self_manager.update_bundler_and_restart_with_it_if_needed(target_ver.to_s)
        expect(Bundler.ui).to have_received(:info).with("Updating bundler to #{target_ver}.")
        expect(mock_source).to have_received(:install).with(mock_spec)
      end

      it "restarts with the new version after installation" do
        self_manager.update_bundler_and_restart_with_it_if_needed(target_ver.to_s)
        expect(Kernel).to have_received(:exec).with(
          hash_including("BUNDLER_VERSION" => target_ver.to_s),
          any_args
        )
        expect(Bundler).to have_received(:with_original_env)
      end
    end

    context "when a newer version is found and already installed" do
      let(:current_ver) { Gem::Version.new("2.4.0") }
      let(:target_ver) { Gem::Version.new("2.5.0") }
      let(:mock_source) { double("source") }
      let(:mock_spec) do
        spec = double("spec", version: target_ver, name: "bundler", source: mock_source)
        allow(spec).to receive(:<=>).and_return(0)
        spec
      end

      before do
        allow(Bundler).to receive(:gem_version).and_return(current_ver)
        allow(Bundler).to receive(:configure)

        local_source = double("local_source")
        allow(local_source).to receive(:specs).and_return(double(select: [mock_spec]))
        allow(Bundler::Source::Rubygems).to receive(:new).with("allow_local" => true).and_return(local_source)

        # installed? returns truthy → skip install
        allow(Bundler.rubygems).to receive(:find_bundler).with(target_ver.to_s).and_return(true)
        allow(mock_source).to receive(:install)
        allow(Bundler).to receive(:with_original_env).and_yield
        allow(Kernel).to receive(:exec)
        allow(Bundler.ui).to receive(:info)
      end

      it "skips installation and restarts directly with the target version" do
        self_manager.update_bundler_and_restart_with_it_if_needed(target_ver.to_s)
        expect(mock_source).not_to have_received(:install)
        expect(Kernel).to have_received(:exec).with(
          hash_including("BUNDLER_VERSION" => target_ver.to_s),
          any_args
        )
      end
    end

    context "when the target version does not exist in any source" do
      before do
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.4.0"))
        allow(Bundler).to receive(:configure)

        # Local source returns no matching specs
        local_source = double("local_source")
        allow(local_source).to receive(:specs).and_return(double(select: []))
        allow(Bundler::Source::Rubygems).to receive(:new).with("allow_local" => true).and_return(local_source)

        # Remote source also returns no matching specs
        remote_source = double("remote_source")
        allow(remote_source).to receive(:remote!)
        allow(remote_source).to receive(:add_dependency_names)
        allow(remote_source).to receive(:specs).and_return(double(select: []))
        allow(Bundler::Source::Rubygems).to receive(:new).with("remotes" => "https://rubygems.org").and_return(remote_source)
      end

      it "raises Bundler::InvalidOption with a descriptive message" do
        expect {
          self_manager.update_bundler_and_restart_with_it_if_needed("99.99.99")
        }.to raise_error(Bundler::InvalidOption, /target version \(99\.99\.99\) does not exist/)
        expect(Bundler).to have_received(:configure)
      end
    end

    context "when running an older version and target is a non-specific requirement" do
      let(:current_ver) { Gem::Version.new("2.4.0") }
      let(:resolved_ver) { Gem::Version.new("2.6.0") }
      let(:mock_source) { double("source") }
      let(:mock_spec) do
        spec = double("spec", version: resolved_ver, name: "bundler", source: mock_source)
        allow(spec).to receive(:<=>).and_return(0)
        allow(spec).to receive(:matches_current_metadata?).and_return(true)
        spec
      end

      before do
        allow(Bundler).to receive(:gem_version).and_return(current_ver)
        allow(Bundler).to receive(:configure)

        # Local source has no matching spec for the non-specific requirement
        local_source = double("local_source")
        allow(local_source).to receive(:specs).and_return(double(select: []))
        allow(Bundler::Source::Rubygems).to receive(:new).with("allow_local" => true).and_return(local_source)

        # Remote source resolves to the newer version
        remote_source = double("remote_source")
        allow(remote_source).to receive(:remote!)
        allow(remote_source).to receive(:add_dependency_names)
        allow(remote_source).to receive(:specs).and_return(double(select: [mock_spec]))
        allow(Bundler::Source::Rubygems).to receive(:new).with("remotes" => "https://rubygems.org").and_return(remote_source)

        allow(Bundler.rubygems).to receive(:find_bundler).with(resolved_ver.to_s).and_return(nil)
        allow(mock_source).to receive(:install).with(mock_spec)
        allow(Bundler).to receive(:with_original_env).and_yield
        allow(Kernel).to receive(:exec)
        allow(Bundler.ui).to receive(:info)
      end

      it "resolves the latest matching version and proceeds with update" do
        self_manager.update_bundler_and_restart_with_it_if_needed(">= 2.5.0")
        expect(Bundler.ui).to have_received(:info).with("Updating bundler to #{resolved_ver}.")
        expect(Kernel).to have_received(:exec).with(
          hash_including("BUNDLER_VERSION" => resolved_ver.to_s),
          any_args
        )
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Context: update detection
  # Verifies find_restart_version private method behavior through public
  # method invocations, ensuring correct detection of when a restart is needed.
  # ---------------------------------------------------------------------------
  context "update detection" do
    describe "restart detection via restart_with_locked_bundler_if_needed" do
      it "detects restart is needed when lockfile version differs from current running version" do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.5.0")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.4.0"))
        allow(Bundler).to receive(:configure)
        allow(Bundler.rubygems).to receive(:find_bundler).with("2.5.0").and_return(true)
        allow(self_manager).to receive(:ruby_can_restart_with_same_arguments?).and_return(true)
        allow(Bundler).to receive(:with_original_env).and_yield
        allow(Kernel).to receive(:exec)

        self_manager.restart_with_locked_bundler_if_needed
        expect(Kernel).to have_received(:exec)
        expect(Bundler::LockfileParser).to have_received(:bundled_with)
      end

      it "does not detect restart when lockfile version is a dev version" do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.5.0.dev")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.4.0"))
        allow(self_manager).to receive(:ruby_can_restart_with_same_arguments?).and_return(true)

        result = self_manager.restart_with_locked_bundler_if_needed
        expect(result).to be_nil
        expect(Bundler::LockfileParser).to have_received(:bundled_with)
      end

      it "does not detect restart when no lockfile version is available" do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return(nil)
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.4.0"))

        result = self_manager.restart_with_locked_bundler_if_needed
        expect(result).to be_nil
        expect(Bundler::LockfileParser).to have_received(:bundled_with)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Context: version switching
  # Validates that the correct version is selected based on lockfile_version
  # and configured_version settings.
  # ---------------------------------------------------------------------------
  context "version switching" do
    it "uses lockfile version when settings[:version] is 'lockfile'" do
      allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
      allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
      allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.6.0")
      allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.4.0"))
      allow(Bundler).to receive(:configure)
      allow(Bundler.rubygems).to receive(:find_bundler).with("2.6.0").and_return(true)
      allow(self_manager).to receive(:ruby_can_restart_with_same_arguments?).and_return(true)
      allow(Bundler).to receive(:with_original_env).and_yield
      allow(Kernel).to receive(:exec)

      self_manager.restart_with_locked_bundler_if_needed
      expect(Kernel).to have_received(:exec).with(
        hash_including("BUNDLER_VERSION" => "2.6.0"),
        any_args
      )
      expect(Bundler::LockfileParser).to have_received(:bundled_with)
    end

    it "uses configured version when settings[:version] is a specific version string" do
      allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
      allow(Bundler.settings).to receive(:[]).with(:version).and_return("2.7.0")
      allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.5.0")
      allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.4.0"))
      allow(Bundler).to receive(:configure)
      allow(Bundler.rubygems).to receive(:find_bundler).with("2.7.0").and_return(true)
      allow(self_manager).to receive(:ruby_can_restart_with_same_arguments?).and_return(true)
      allow(Bundler).to receive(:with_original_env).and_yield
      allow(Kernel).to receive(:exec)

      self_manager.restart_with_locked_bundler_if_needed
      expect(Kernel).to have_received(:exec).with(
        hash_including("BUNDLER_VERSION" => "2.7.0"),
        any_args
      )
      expect(Bundler.settings).to have_received(:[]).with(:version)
    end

    it "does not switch when configured version is 'system'" do
      allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
      allow(Bundler.settings).to receive(:[]).with(:version).and_return("system")
      allow(Bundler.ui).to receive(:info)

      result = self_manager.restart_with_locked_bundler_if_needed
      expect(result).to be_nil
      expect(Bundler.settings).to have_received(:[]).with(:version)
    end
  end

  # ---------------------------------------------------------------------------
  # Context: restart behavior
  # Validates that restart_with is invoked with the correct version and that
  # the Kernel.exec call is properly wrapped within Bundler.with_original_env.
  # ---------------------------------------------------------------------------
  context "restart behavior" do
    before do
      allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
      allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
      allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.5.0")
      allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.4.0"))
      allow(Bundler).to receive(:configure)
      allow(Bundler.rubygems).to receive(:find_bundler).with("2.5.0").and_return(true)
      allow(self_manager).to receive(:ruby_can_restart_with_same_arguments?).and_return(true)
      allow(Bundler).to receive(:with_original_env).and_yield
      allow(Kernel).to receive(:exec)
    end

    it "wraps the Kernel.exec call within Bundler.with_original_env" do
      self_manager.restart_with_locked_bundler_if_needed
      expect(Bundler).to have_received(:with_original_env)
      expect(Kernel).to have_received(:exec)
    end

    it "passes the correct BUNDLER_VERSION environment variable to Kernel.exec" do
      self_manager.restart_with_locked_bundler_if_needed
      expect(Kernel).to have_received(:exec).with(
        hash_including("BUNDLER_VERSION" => "2.5.0"),
        any_args
      )
      expect(Bundler.rubygems).to have_received(:find_bundler).with("2.5.0")
    end

    it "includes GEM_HOME and GEM_PATH related env vars in the exec call" do
      self_manager.restart_with_locked_bundler_if_needed
      expect(Kernel).to have_received(:exec).with(
        hash_including(
          "BUNDLER_VERSION" => "2.5.0",
          "GEM_HOME" => anything,
          "GEM_PATH" => anything
        ),
        any_args
      )
      expect(Bundler).to have_received(:configure)
    end
  end

  # ---------------------------------------------------------------------------
  # Class interface validation
  # ---------------------------------------------------------------------------
  describe "class interface" do
    it "can be instantiated without arguments and is a SelfManager instance" do
      instance = described_class.new
      expect(instance).to be_a(Bundler::SelfManager)
      expect(instance).to be_a(described_class)
    end

    it "responds to all three public self-management methods" do
      expect(self_manager).to respond_to(:restart_with_locked_bundler_if_needed)
      expect(self_manager).to respond_to(:install_locked_bundler_and_restart_with_it_if_needed)
      expect(self_manager).to respond_to(:update_bundler_and_restart_with_it_if_needed)
    end
  end
end
