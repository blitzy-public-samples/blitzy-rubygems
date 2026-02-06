# frozen_string_literal: true

require "spec_helper"
require "bundler/self_manager"

RSpec.describe Bundler::SelfManager do
  let(:self_manager) { described_class.new }

  describe "#restart_with_locked_bundler_if_needed" do
    context "when find_restart_version returns nil" do
      it "returns nil without attempting restart" do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(false)
        result = self_manager.restart_with_locked_bundler_if_needed
        expect(result).to be_nil
      end
    end

    context "when find_restart_version returns a version but it is not installed" do
      let(:restart_version) { Gem::Version.new("2.4.0") }

      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))
        allow(Bundler).to receive(:configure)
        allow(Bundler.rubygems).to receive(:find_bundler).with("2.4.0").and_return(nil)
      end

      it "returns nil without attempting restart" do
        result = self_manager.restart_with_locked_bundler_if_needed
        expect(result).to be_nil
      end
    end

    context "when restart version is found and installed" do
      let(:restart_version) { Gem::Version.new("2.4.0") }

      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))
        allow(Bundler).to receive(:configure)
        allow(Bundler.rubygems).to receive(:find_bundler).with("2.4.0").and_return(true)
      end

      it "calls restart_with with the version" do
        # restart_with calls Kernel.exec which we must mock to prevent process exit
        allow(Bundler).to receive(:with_original_env).and_yield
        expect(Kernel).to receive(:exec).with(hash_including("BUNDLER_VERSION" => "2.4.0"), any_args)
        self_manager.restart_with_locked_bundler_if_needed
      end
    end

    context "when BUNDLER_VERSION env is set" do
      it "returns nil because autoswitching does not apply" do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))

        old_bundler_version = ENV["BUNDLER_VERSION"]
        begin
          ENV["BUNDLER_VERSION"] = "2.3.0"
          result = self_manager.restart_with_locked_bundler_if_needed
          expect(result).to be_nil
        ensure
          ENV["BUNDLER_VERSION"] = old_bundler_version
        end
      end
    end
  end

  describe "#install_locked_bundler_and_restart_with_it_if_needed" do
    context "when find_restart_version returns nil" do
      it "returns nil without attempting install or restart" do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(false)
        result = self_manager.install_locked_bundler_and_restart_with_it_if_needed
        expect(result).to be_nil
      end
    end

    context "when restart version equals lockfile version" do
      let(:version_str) { "2.4.0" }

      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return(version_str)
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))
        allow(Bundler).to receive(:configure)
      end

      it "displays the lockfile version message via Bundler.ui" do
        # Allow install_and_restart_with to be stubbed since it makes network calls
        allow(self_manager).to receive(:install_and_restart_with)

        expect(Bundler.ui).to receive(:info).with(
          a_string_including("your lockfile was generated with #{version_str}")
        )

        self_manager.install_locked_bundler_and_restart_with_it_if_needed
      end
    end

    context "when restart version differs from lockfile version (configured version)" do
      let(:configured_version) { "2.5.0" }

      before do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return(configured_version)
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))
        allow(Bundler).to receive(:configure)
      end

      it "displays the configuration version message via Bundler.ui" do
        allow(self_manager).to receive(:install_and_restart_with)

        expect(Bundler.ui).to receive(:info).with(
          a_string_including("your configuration was #{configured_version}")
        )

        self_manager.install_locked_bundler_and_restart_with_it_if_needed
      end
    end

    context "when configured version is 'system'" do
      it "returns nil without attempting install" do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler.settings).to receive(:[]).with(:version).and_return("system")

        result = self_manager.install_locked_bundler_and_restart_with_it_if_needed
        expect(result).to be_nil
      end
    end
  end

  describe "#update_bundler_and_restart_with_it_if_needed" do
    context "when resolve_update_version_from returns nil (no update needed)" do
      let(:current_ver) { Gem::Version.new("2.5.0") }

      before do
        allow(Bundler).to receive(:gem_version).and_return(current_ver)
        allow(Bundler).to receive(:configure)
      end

      it "returns nil when already running the target version" do
        # Create a mock spec matching the current version
        mock_spec = double("spec", version: current_ver, name: "bundler")
        allow(mock_spec).to receive(:source).and_return(double("source"))
        allow(mock_spec).to receive(:<=>).and_return(0)

        local_source = double("local_source")
        allow(local_source).to receive(:specs).and_return(double(select: [mock_spec]))
        allow(Bundler::Source::Rubygems).to receive(:new).with("allow_local" => true).and_return(local_source)

        result = self_manager.update_bundler_and_restart_with_it_if_needed("2.5.0")
        expect(result).to be_nil
      end
    end

    context "when a newer version is found" do
      let(:current_ver) { Gem::Version.new("2.4.0") }
      let(:target_ver) { Gem::Version.new("2.5.0") }
      let(:mock_source) { double("source") }
      let(:mock_spec) { double("spec", version: target_ver, name: "bundler", source: mock_source) }

      before do
        allow(Bundler).to receive(:gem_version).and_return(current_ver)
        allow(Bundler).to receive(:configure)
        allow(mock_spec).to receive(:<=>).and_return(0)

        local_source = double("local_source")
        allow(local_source).to receive(:specs).and_return(double(select: [mock_spec]))
        allow(Bundler::Source::Rubygems).to receive(:new).with("allow_local" => true).and_return(local_source)
      end

      it "displays updating message via Bundler.ui" do
        allow(Bundler.rubygems).to receive(:find_bundler).and_return(nil)
        allow(mock_source).to receive(:install).with(mock_spec)
        allow(Bundler).to receive(:with_original_env).and_yield
        allow(Kernel).to receive(:exec)

        expect(Bundler.ui).to receive(:info).with("Updating bundler to #{target_ver}.")
        self_manager.update_bundler_and_restart_with_it_if_needed(target_ver.to_s)
      end

      it "installs the spec if not already installed" do
        allow(Bundler.rubygems).to receive(:find_bundler).with(target_ver.to_s).and_return(nil)
        allow(Bundler).to receive(:with_original_env).and_yield
        allow(Kernel).to receive(:exec)
        allow(Bundler.ui).to receive(:info)

        expect(mock_source).to receive(:install).with(mock_spec)
        self_manager.update_bundler_and_restart_with_it_if_needed(target_ver.to_s)
      end

      it "does not install if already installed" do
        allow(Bundler.rubygems).to receive(:find_bundler).with(target_ver.to_s).and_return(true)
        allow(Bundler).to receive(:with_original_env).and_yield
        allow(Kernel).to receive(:exec)
        allow(Bundler.ui).to receive(:info)

        expect(mock_source).not_to receive(:install)
        self_manager.update_bundler_and_restart_with_it_if_needed(target_ver.to_s)
      end

      it "calls restart_with to exec into the new version" do
        allow(Bundler.rubygems).to receive(:find_bundler).with(target_ver.to_s).and_return(true)
        allow(Bundler.ui).to receive(:info)
        allow(Bundler).to receive(:with_original_env).and_yield

        expect(Kernel).to receive(:exec).with(
          hash_including("BUNDLER_VERSION" => target_ver.to_s),
          any_args
        )
        self_manager.update_bundler_and_restart_with_it_if_needed(target_ver.to_s)
      end
    end

    context "when target version does not exist" do
      before do
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.4.0"))
        allow(Bundler).to receive(:configure)

        local_source = double("local_source")
        allow(local_source).to receive(:specs).and_return(double(select: []))
        allow(Bundler::Source::Rubygems).to receive(:new).with("allow_local" => true).and_return(local_source)

        remote_source = double("remote_source")
        allow(remote_source).to receive(:remote!)
        allow(remote_source).to receive(:add_dependency_names)
        allow(remote_source).to receive(:specs).and_return(double(select: []))
        allow(Bundler::Source::Rubygems).to receive(:new).with("remotes" => "https://rubygems.org").and_return(remote_source)
      end

      it "raises InvalidOption with a descriptive message" do
        expect {
          self_manager.update_bundler_and_restart_with_it_if_needed("99.99.99")
        }.to raise_error(Bundler::InvalidOption, /target version \(99\.99\.99\) does not exist/)
      end
    end
  end

  describe "private method behavior (via send)" do
    describe "#needs_switching?" do
      it "returns true when autoswitching applies, version is released, and not currently running" do
        allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")

        version = Gem::Version.new("2.4.0")
        result = self_manager.send(:needs_switching?, version)
        expect(result).to be_truthy
      end

      it "returns false when running the same version" do
        current = Gem::Version.new("2.4.0")
        allow(Bundler).to receive(:gem_version).and_return(current)
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")

        result = self_manager.send(:needs_switching?, current)
        expect(result).to be_falsey
      end

      it "returns false for dev versions" do
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0.dev")

        version = Gem::Version.new("2.4.0.dev")
        result = self_manager.send(:needs_switching?, version)
        expect(result).to be_falsey
      end
    end

    describe "#released?" do
      it "returns true for a standard release version" do
        version = Gem::Version.new("2.4.0")
        expect(self_manager.send(:released?, version)).to eq(true)
      end

      it "returns false for a dev version" do
        version = Gem::Version.new("2.4.0.dev")
        expect(self_manager.send(:released?, version)).to eq(false)
      end

      it "returns true for a pre-release version that does not end in .dev" do
        version = Gem::Version.new("2.4.0.rc1")
        expect(self_manager.send(:released?, version)).to eq(true)
      end
    end

    describe "#running?" do
      it "returns true when version matches current_version" do
        current = Gem::Version.new("2.4.0")
        allow(Bundler).to receive(:gem_version).and_return(current)

        expect(self_manager.send(:running?, current)).to eq(true)
      end

      it "returns false when version does not match current_version" do
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))

        expect(self_manager.send(:running?, Gem::Version.new("2.4.0"))).to eq(false)
      end
    end

    describe "#running_older_than?" do
      it "returns true when current version is older" do
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))

        expect(self_manager.send(:running_older_than?, Gem::Version.new("2.4.0"))).to eq(true)
      end

      it "returns false when current version is newer" do
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.5.0"))

        expect(self_manager.send(:running_older_than?, Gem::Version.new("2.4.0"))).to eq(false)
      end

      it "returns false when versions are equal" do
        allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.4.0"))

        expect(self_manager.send(:running_older_than?, Gem::Version.new("2.4.0"))).to eq(false)
      end
    end

    describe "#current_version" do
      it "returns the Bundler gem version" do
        expected = Bundler.gem_version
        expect(self_manager.send(:current_version)).to eq(expected)
      end

      it "memoizes the result" do
        first_call = self_manager.send(:current_version)
        second_call = self_manager.send(:current_version)
        expect(first_call).to equal(second_call)
      end
    end

    describe "#lockfile_version" do
      context "when a valid lockfile version exists" do
        it "returns a Gem::Version parsed from bundled_with" do
          allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.1")

          result = self_manager.send(:lockfile_version)
          expect(result).to eq(Gem::Version.new("2.4.1"))
          expect(result).to be_a(Gem::Version)
        end
      end

      context "when bundled_with returns nil" do
        it "returns nil" do
          allow(Bundler::LockfileParser).to receive(:bundled_with).and_return(nil)

          expect(self_manager.send(:lockfile_version)).to be_nil
        end
      end

      context "when bundled_with returns an invalid version string" do
        it "returns nil due to ArgumentError rescue" do
          allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("not_a_version")

          expect(self_manager.send(:lockfile_version)).to be_nil
        end
      end

      it "memoizes the result" do
        allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")

        first_call = self_manager.send(:lockfile_version)
        # Should not call bundled_with again
        expect(Bundler::LockfileParser).to have_received(:bundled_with).once
        second_call = self_manager.send(:lockfile_version)
        expect(first_call).to equal(second_call)
      end
    end

    describe "#find_restart_version" do
      context "when not in a bundle" do
        it "returns nil" do
          allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(false)

          expect(self_manager.send(:find_restart_version)).to be_nil
        end
      end

      context "when configured_version is 'system'" do
        it "returns nil" do
          allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
          allow(Bundler.settings).to receive(:[]).with(:version).and_return("system")

          expect(self_manager.send(:find_restart_version)).to be_nil
        end
      end

      context "when configured_version is 'lockfile'" do
        it "uses the lockfile version for the restart version" do
          allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
          allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
          allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
          allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))

          result = self_manager.send(:find_restart_version)
          expect(result).to eq(Gem::Version.new("2.4.0"))
        end
      end

      context "when configured_version is a specific version string" do
        it "creates a Gem::Version from the configured version" do
          allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
          allow(Bundler.settings).to receive(:[]).with(:version).and_return("2.5.0")
          allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
          allow(Bundler).to receive(:gem_version).and_return(Gem::Version.new("2.3.0"))

          result = self_manager.send(:find_restart_version)
          expect(result).to eq(Gem::Version.new("2.5.0"))
        end
      end

      context "when needs_switching? returns false (already running that version)" do
        it "returns nil" do
          current = Gem::Version.new("2.4.0")
          allow(Bundler::SharedHelpers).to receive(:in_bundle?).and_return(true)
          allow(Bundler.settings).to receive(:[]).with(:version).and_return("lockfile")
          allow(Bundler::LockfileParser).to receive(:bundled_with).and_return("2.4.0")
          allow(Bundler).to receive(:gem_version).and_return(current)

          expect(self_manager.send(:find_restart_version)).to be_nil
        end
      end
    end

    describe "#ruby_can_restart_with_same_arguments?" do
      it "returns true when PROGRAM_NAME is not -e" do
        # In normal test execution, $PROGRAM_NAME should not be "-e"
        expect(self_manager.send(:ruby_can_restart_with_same_arguments?)).to eq($PROGRAM_NAME != "-e")
      end
    end

    describe "#installed?" do
      it "checks if the given bundler version is installed via Bundler.rubygems" do
        allow(Bundler).to receive(:configure)
        allow(Bundler.rubygems).to receive(:find_bundler).with("2.4.0").and_return(true)

        expect(self_manager.send(:installed?, Gem::Version.new("2.4.0"))).to be_truthy
      end

      it "returns nil/falsey when the version is not found" do
        allow(Bundler).to receive(:configure)
        allow(Bundler.rubygems).to receive(:find_bundler).with("99.0.0").and_return(nil)

        expect(self_manager.send(:installed?, Gem::Version.new("99.0.0"))).to be_falsey
      end
    end
  end

  describe "class instantiation" do
    it "can be instantiated without arguments" do
      instance = described_class.new
      expect(instance).to be_a(Bundler::SelfManager)
    end

    it "responds to the three public methods" do
      expect(self_manager).to respond_to(:restart_with_locked_bundler_if_needed)
      expect(self_manager).to respond_to(:install_locked_bundler_and_restart_with_it_if_needed)
      expect(self_manager).to respond_to(:update_bundler_and_restart_with_it_if_needed)
    end
  end
end
