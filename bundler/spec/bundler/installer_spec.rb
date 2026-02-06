# frozen_string_literal: true

require "spec_helper"
require "bundler/installer"

# RSpec unit tests for Bundler::Installer covering .install, #initialize, #run,
# parallel installation, post-install hooks, standalone mode, binstub generation,
# and spec compatibility checking. All tests invoke real Installer methods with
# controlled definition doubles and external dependency stubs.
RSpec.describe Bundler::Installer do
  # Ensure Plugin::Events constants are defined; other specs (events_spec.rb)
  # may call Events.reset which removes all dynamically-defined constants.
  before do
    unless Bundler::Plugin::Events.const_defined?(:GEM_BEFORE_INSTALL_ALL)
      verbose = $VERBOSE
      $VERBOSE = nil
      load "bundler/plugin/events.rb"
      $VERBOSE = verbose
    end
  end

  let(:root) { bundled_app }

  let(:dependencies) do
    [double("dep1", name: "rake"), double("dep2", name: "rspec")]
  end

  let(:specs) do
    spec1 = double("spec1",
      name: "rake",
      version: Gem::Version.new("13.0"),
      full_name: "rake-13.0",
      matches_current_ruby?: true,
      matches_current_rubygems?: true)
    spec2 = double("spec2",
      name: "rspec",
      version: Gem::Version.new("3.12"),
      full_name: "rspec-3.12",
      matches_current_ruby?: true,
      matches_current_rubygems?: true)
    [spec1, spec2]
  end

  let(:definition) do
    instance_double("Bundler::Definition",
      dependencies: dependencies,
      specs: specs,
      lock: nil)
  end

  # ---------------------------------------------------------------------------
  # .install class method
  # ---------------------------------------------------------------------------
  describe ".install" do
    before do
      allow(Bundler::Plugin).to receive(:hook)
      allow(Bundler::ProcessLock).to receive(:lock).and_yield
      allow(Bundler).to receive(:create_bundle_path)
      allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
      allow(definition).to receive(:setup_domain!).and_return(false)
      allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
      allow(Gem::Specification).to receive(:reset)
    end

    it "creates an Installer instance and returns it with correct type" do
      result = described_class.install(root, definition, {})

      expect(result).to be_a(described_class)
      expect(result).to respond_to(:run)
    end

    it "fires GEM_BEFORE_INSTALL_ALL then GEM_AFTER_INSTALL_ALL plugin hooks in order" do
      expect(Bundler::Plugin).to receive(:hook).with(
        Bundler::Plugin::Events::GEM_BEFORE_INSTALL_ALL,
        dependencies
      ).ordered
      expect(Bundler::Plugin).to receive(:hook).with(
        Bundler::Plugin::Events::GEM_AFTER_INSTALL_ALL,
        dependencies
      ).ordered

      described_class.install(root, definition, {})
    end

    it "returns an installer with accessible definition and empty post_install_messages" do
      installer = described_class.install(root, definition, {})

      expect(installer.definition).to eq(definition)
      expect(installer.post_install_messages).to eq({})
    end

    it "invokes run on the installer between the plugin hooks" do
      installer = described_class.install(root, definition, {})

      expect(installer).to be_a(described_class)
      expect(installer.post_install_messages).to be_a(Hash)
    end
  end

  # ---------------------------------------------------------------------------
  # #initialize constructor
  # ---------------------------------------------------------------------------
  describe "#initialize" do
    subject { described_class.new(root, definition) }

    it "stores the definition and makes it accessible via attr_reader" do
      expect(subject.definition).to eq(definition)
      expect(subject).to respond_to(:definition)
    end

    it "initializes post_install_messages as an empty Hash" do
      expect(subject.post_install_messages).to eq({})
      expect(subject.post_install_messages).to be_a(Hash)
    end

    it "returns nil for non-existent keys in post_install_messages" do
      expect(subject.post_install_messages["nonexistent"]).to be_nil
      expect(subject.post_install_messages.empty?).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # #run orchestration method
  # ---------------------------------------------------------------------------
  describe "#run" do
    subject { described_class.new(root, definition) }

    before do
      allow(Bundler).to receive(:create_bundle_path)
      allow(Bundler::ProcessLock).to receive(:lock).and_yield
      allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
      allow(Gem::Specification).to receive(:reset)
    end

    context "when there are no dependencies" do
      let(:definition) do
        instance_double("Bundler::Definition",
          dependencies: [],
          specs: [],
          lock: nil)
      end

      before do
        allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
      end

      it "warns about empty Gemfile and locks the definition" do
        expect(Bundler.ui).to receive(:warn).with("The Gemfile specifies no dependencies")
        expect(definition).to receive(:lock)

        subject.run({})
      end

      it "does not invoke the parallel install process and leaves messages empty" do
        allow(Bundler.ui).to receive(:warn)
        allow(definition).to receive(:lock)

        expect(Bundler::ParallelInstaller).not_to receive(:call)

        subject.run({})
        expect(subject.post_install_messages).to eq({})
      end
    end

    context "when dependencies exist" do
      before do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
      end

      it "creates the bundle path and acquires a ProcessLock" do
        expect(Bundler).to receive(:create_bundle_path)
        expect(Bundler::ProcessLock).to receive(:lock).and_yield

        subject.run({})
      end

      it "ensures gemfile and lockfile equivalence with nil deployment by default" do
        expect(definition).to receive(:ensure_equivalent_gemfile_and_lockfile).with(nil)

        subject.run({})
        expect(subject.post_install_messages).to be_a(Hash)
      end

      it "passes deployment flag to ensure_equivalent_gemfile_and_lockfile when specified" do
        expect(definition).to receive(:ensure_equivalent_gemfile_and_lockfile).with(true)

        subject.run(deployment: true)
        expect(subject.definition).to eq(definition)
      end

      it "resets Gem::Specification cache and locks definition after installation" do
        expect(Gem::Specification).to receive(:reset)
        expect(definition).to receive(:lock)

        subject.run({})
      end
    end

    context "when setup_domain! returns true" do
      before do
        allow(definition).to receive(:setup_domain!).and_return(true)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
        allow(Gem).to receive(:load_plugins)
        allow(Gem).to receive(:load_plugin_files)
        allow(Gem).to receive(:load_env_plugins)
        allow(definition).to receive_message_chain(:specs, :select).and_return([])
      end

      it "checks spec compatibility and loads plugins without error" do
        expect(Gem).to receive(:load_plugins)
        expect { subject.run({}) }.not_to raise_error
      end

      it "calls load_env_plugins and completes successfully" do
        expect(Gem).to receive(:load_env_plugins)

        subject.run({})
        expect(subject.post_install_messages).to eq({})
      end
    end

    context "when setup_domain! returns false" do
      before do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
      end

      it "skips plugin loading and spec compatibility check" do
        expect(Gem).not_to receive(:load_plugins)

        subject.run({})
        expect(subject.post_install_messages).to eq({})
      end
    end

    context "when create_bundle_path raises an error" do
      it "propagates the error and does not modify post_install_messages" do
        allow(Bundler).to receive(:create_bundle_path).and_raise(
          Bundler::PermissionError.new("vendor/bundle")
        )

        expect { subject.run({}) }.to raise_error(Bundler::PermissionError)
        expect(subject.post_install_messages).to eq({})
      end
    end

    # -------------------------------------------------------------------------
    # standalone mode
    # -------------------------------------------------------------------------
    context "when standalone option is specified" do
      let(:standalone_instance) { double("Standalone", generate: nil) }

      before do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
      end

      it "generates standalone setup files via Standalone" do
        expect(Bundler::Standalone).to receive(:new).with(true, definition).and_return(standalone_instance)
        expect(standalone_instance).to receive(:generate)

        subject.run(standalone: true)
      end

      it "passes the standalone groups to Standalone.new" do
        groups = [:default, :development]
        expect(Bundler::Standalone).to receive(:new).with(groups, definition).and_return(standalone_instance)

        subject.run(standalone: groups)
        expect(subject.post_install_messages).to eq({})
      end
    end

    context "when standalone option is not specified" do
      before do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
      end

      it "does not generate standalone setup" do
        expect(Bundler::Standalone).not_to receive(:new)

        subject.run({})
        expect(subject.post_install_messages).to eq({})
      end
    end

    # -------------------------------------------------------------------------
    # post-install hooks / messages
    # -------------------------------------------------------------------------
    context "when installations have post-install messages" do
      let(:installation_with_msg) do
        double("Installation",
          name: "rake",
          has_post_install_message?: true,
          post_install_message: "Thanks for installing rake!")
      end

      let(:installation_without_msg) do
        double("Installation",
          name: "rspec",
          has_post_install_message?: false)
      end

      before do
        allow(definition).to receive(:setup_domain!).and_return(false)
      end

      it "collects post_install_messages from installations that have messages" do
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([installation_with_msg])

        subject.run({})

        expect(subject.post_install_messages).to have_key("rake")
        expect(subject.post_install_messages).to eq("rake" => "Thanks for installing rake!")
      end

      it "does not add entries for installations without post-install messages" do
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([installation_without_msg])

        subject.run({})

        expect(subject.post_install_messages).to eq({})
        expect(subject.post_install_messages["rspec"]).to be_nil
      end

      it "collects messages selectively from mixed installations" do
        allow(Bundler::ParallelInstaller).to receive(:call).and_return(
          [installation_with_msg, installation_without_msg]
        )

        subject.run({})

        expect(subject.post_install_messages).to include("rake" => "Thanks for installing rake!")
        expect(subject.post_install_messages.keys).not_to include("rspec")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #generate_bundler_executable_stubs
  # ---------------------------------------------------------------------------
  describe "#generate_bundler_executable_stubs" do
    subject { described_class.new(root, definition) }

    context "when spec is for bundler itself" do
      let(:bundler_spec) { double("Spec", name: "bundler") }

      it "warns about bundler and does not generate stubs" do
        expect(Bundler.ui).to receive(:warn).with(
          "Bundler itself does not use binstubs because its version is selected by RubyGems"
        )

        subject.generate_bundler_executable_stubs(bundler_spec)
        expect(subject.post_install_messages).to eq({})
      end
    end

    context "when binstubs_cmd is set and spec has no executables" do
      let(:spec_without_executables) do
        double("Spec",
          name: "activesupport",
          executables: [])
      end

      context "when runtime dependencies have executables" do
        let(:dep_spec) { double("DepSpec", executables: ["rails"]) }
        let(:dep) { double("Dep", name: "railties") }
        let(:dep_specs) { double("DepSpecs", first: dep_spec) }

        before do
          allow(spec_without_executables).to receive(:runtime_dependencies).and_return([dep])
          allow(definition).to receive(:specs).and_return(double("Specs", :[] => dep_specs))
        end

        it "warns about executables available in dependent gems" do
          expect(Bundler.ui).to receive(:warn).with(
            "activesupport has no executables, but you may want one from a gem it depends on."
          )
          expect(Bundler.ui).to receive(:warn).with("  railties has: rails")

          subject.generate_bundler_executable_stubs(spec_without_executables, binstubs_cmd: true)
        end
      end

      context "when runtime dependencies have no executables either" do
        let(:dep_spec) { double("DepSpec", executables: []) }
        let(:dep) { double("Dep", name: "concurrent-ruby") }
        let(:dep_specs) { double("DepSpecs", first: dep_spec) }

        before do
          allow(spec_without_executables).to receive(:runtime_dependencies).and_return([dep])
          allow(definition).to receive(:specs).and_return(double("Specs", :[] => dep_specs))
        end

        it "warns there are no executables for the gem at all" do
          expect(Bundler.ui).to receive(:warn).with(
            "There are no executables for the gem activesupport."
          )

          subject.generate_bundler_executable_stubs(spec_without_executables, binstubs_cmd: true)
          expect(subject.post_install_messages).to be_a(Hash)
        end
      end
    end

    context "when spec has executables" do
      let(:bin_path) { tmpdir("bins") }
      let(:spec_with_executables) do
        double("Spec",
          name: "rake",
          executables: ["rake"])
      end

      before do
        FileUtils.mkdir_p(bin_path)
        allow(Bundler).to receive(:bin_path).and_return(bin_path)
        allow(Bundler).to receive(:default_gemfile).and_return(bundled_app("Gemfile"))
      end

      after do
        FileUtils.rm_rf(bin_path) if bin_path.exist?
      end

      it "writes binstub files for each executable when force is true" do
        subject.generate_bundler_executable_stubs(spec_with_executables, force: true)

        expect(File.exist?(bin_path.join("rake"))).to be true
        expect(File.read(bin_path.join("rake")).length).to be > 0
      end

      it "preserves existing binstubs when force is not set" do
        File.write(bin_path.join("rake"), "existing content")

        subject.generate_bundler_executable_stubs(spec_with_executables)

        expect(File.exist?(bin_path.join("rake"))).to be true
        expect(File.read(bin_path.join("rake"))).to eq("existing content")
      end

      it "overwrites existing binstubs when force option is set" do
        File.write(bin_path.join("rake"), "old content")

        subject.generate_bundler_executable_stubs(spec_with_executables, force: true)

        content = File.read(bin_path.join("rake"))
        expect(content).not_to eq("old content")
        expect(content.length).to be > 0
      end

      context "with binstubs_cmd and a single existing stub" do
        it "warns about skipped single executable and suggests --force" do
          File.write(bin_path.join("rake"), "existing")

          expect(Bundler.ui).to receive(:warn).with("Skipped rake since it already exists.")
          expect(Bundler.ui).to receive(:warn).with("If you want to overwrite skipped stubs, use --force.")

          subject.generate_bundler_executable_stubs(spec_with_executables, binstubs_cmd: true)
        end
      end

      context "with binstubs_cmd and two existing stubs" do
        let(:spec_with_two_executables) do
          double("Spec",
            name: "rspec",
            executables: ["rspec", "rspec-core"])
        end

        it "warns about both skipped executables and suggests --force" do
          File.write(bin_path.join("rspec"), "existing")
          File.write(bin_path.join("rspec-core"), "existing")

          expect(Bundler.ui).to receive(:warn).with(
            "Skipped rspec and rspec-core since they already exist."
          )
          expect(Bundler.ui).to receive(:warn).with(
            "If you want to overwrite skipped stubs, use --force."
          )

          subject.generate_bundler_executable_stubs(spec_with_two_executables, binstubs_cmd: true)
        end
      end

      context "with binstubs_cmd and more than two existing stubs" do
        let(:spec_with_many_executables) do
          double("Spec",
            name: "rails",
            executables: ["rails", "rake", "server"])
        end

        it "warns about all skipped executables with proper formatting" do
          File.write(bin_path.join("rails"), "existing")
          File.write(bin_path.join("rake"), "existing")
          File.write(bin_path.join("server"), "existing")

          expect(Bundler.ui).to receive(:warn).with(
            "Skipped rails, rake and server since they already exist."
          )
          expect(Bundler.ui).to receive(:warn).with(
            "If you want to overwrite skipped stubs, use --force."
          )

          subject.generate_bundler_executable_stubs(spec_with_many_executables, binstubs_cmd: true)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #generate_standalone_bundler_executable_stubs
  # ---------------------------------------------------------------------------
  describe "#generate_standalone_bundler_executable_stubs" do
    subject { described_class.new(root, definition) }

    let(:standalone_bin_path) { tmpdir("standalone_bins") }
    let(:standalone_gem_dir) { tmpdir("standalone_gems", "rake-13.0") }
    let(:spec) do
      double("Spec",
        name: "rake",
        executables: ["rake"],
        full_gem_path: standalone_gem_dir.to_s,
        bindir: "bin")
    end

    before do
      FileUtils.mkdir_p(standalone_bin_path)
      FileUtils.mkdir_p(standalone_gem_dir.join("bin"))
      allow(Bundler).to receive(:bin_path).and_return(standalone_bin_path)
      allow(Bundler).to receive(:root).and_return(root)
      allow(Bundler.settings).to receive(:[]).and_call_original
      allow(Bundler.settings).to receive(:[]).with(:path).and_return("vendor/bundle")
    end

    after do
      FileUtils.rm_rf(standalone_bin_path) if standalone_bin_path.exist?
    end

    it "writes standalone executable stubs for non-bundle executables" do
      subject.generate_standalone_bundler_executable_stubs(spec)

      expect(File.exist?(standalone_bin_path.join("rake"))).to be true
      expect(File.read(standalone_bin_path.join("rake")).length).to be > 0
    end

    it "skips the bundle executable but generates others" do
      spec_with_bundle = double("Spec",
        name: "bundler",
        executables: ["bundle", "bundler"],
        full_gem_path: standalone_gem_dir.to_s,
        bindir: "bin")

      subject.generate_standalone_bundler_executable_stubs(spec_with_bundle)

      expect(File.exist?(standalone_bin_path.join("bundle"))).to be false
      expect(File.exist?(standalone_bin_path.join("bundler"))).to be true
    end

    it "raises RuntimeError when no explicit path is set in settings" do
      allow(Bundler.settings).to receive(:[]).with(:path).and_return(nil)

      expect { subject.generate_standalone_bundler_executable_stubs(spec) }.to raise_error(
        RuntimeError,
        "Can't standalone without an explicit path set"
      )
      expect(File.exist?(standalone_bin_path.join("rake"))).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # ensure_specs_are_compatible! (exercised via #run)
  # ---------------------------------------------------------------------------
  describe "ensure_specs_are_compatible! (via #run)" do
    subject { described_class.new(root, definition) }

    before do
      allow(Bundler).to receive(:create_bundle_path)
      allow(Bundler::ProcessLock).to receive(:lock).and_yield
      allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
      allow(Gem::Specification).to receive(:reset)
    end

    context "when a spec has an incompatible Ruby version" do
      let(:incompatible_spec) do
        double("IncompatSpec",
          name: "some_gem",
          version: Gem::Version.new("1.0"),
          full_name: "some_gem-1.0",
          matches_current_ruby?: false,
          matches_current_rubygems?: true,
          required_ruby_version: ">= 99.0")
      end

      let(:definition) do
        instance_double("Bundler::Definition",
          dependencies: [double("dep", name: "some_gem")],
          specs: [incompatible_spec],
          lock: nil)
      end

      before do
        allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
        allow(definition).to receive(:setup_domain!).and_return(true)
        allow(Gem).to receive(:load_plugins)
        allow(Gem).to receive(:load_plugin_files)
        allow(Gem).to receive(:load_env_plugins)
        allow(definition).to receive_message_chain(:specs, :select).and_return([])
      end

      it "raises InstallError with Ruby version details" do
        expect { subject.run({}) }.to raise_error(
          Bundler::InstallError,
          /some_gem-1.0 requires ruby version >= 99.0/
        )
        expect(subject.post_install_messages).to eq({})
      end
    end

    context "when a spec has an incompatible RubyGems version" do
      let(:incompatible_spec) do
        double("IncompatSpec",
          name: "another_gem",
          version: Gem::Version.new("2.0"),
          full_name: "another_gem-2.0",
          matches_current_ruby?: true,
          matches_current_rubygems?: false,
          required_rubygems_version: ">= 99.0")
      end

      let(:definition) do
        instance_double("Bundler::Definition",
          dependencies: [double("dep", name: "another_gem")],
          specs: [incompatible_spec],
          lock: nil)
      end

      before do
        allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
        allow(definition).to receive(:setup_domain!).and_return(true)
        allow(Gem).to receive(:load_plugins)
        allow(Gem).to receive(:load_plugin_files)
        allow(Gem).to receive(:load_env_plugins)
        allow(definition).to receive_message_chain(:specs, :select).and_return([])
      end

      it "raises InstallError with RubyGems version details" do
        expect { subject.run({}) }.to raise_error(
          Bundler::InstallError,
          /another_gem-2.0 requires rubygems version >= 99.0/
        )
        expect(subject.post_install_messages).to eq({})
      end
    end

    context "when all specs are compatible" do
      before do
        allow(definition).to receive(:setup_domain!).and_return(true)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
        allow(Gem).to receive(:load_plugins)
        allow(Gem).to receive(:load_plugin_files)
        allow(Gem).to receive(:load_env_plugins)
        allow(definition).to receive_message_chain(:specs, :select).and_return([])
      end

      it "completes the installation flow without raising" do
        expect { subject.run({}) }.not_to raise_error
        expect(subject.post_install_messages).to eq({})
      end
    end
  end

  # ---------------------------------------------------------------------------
  # installation parallelization (exercised via #run)
  # ---------------------------------------------------------------------------
  describe "installation parallelization (via #run)" do
    subject { described_class.new(root, definition) }

    before do
      allow(Bundler).to receive(:create_bundle_path)
      allow(Bundler::ProcessLock).to receive(:lock).and_yield
      allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
      allow(definition).to receive(:setup_domain!).and_return(false)
      allow(Gem::Specification).to receive(:reset)
    end

    context "when jobs setting is configured" do
      it "uses the configured number of jobs for parallel installation" do
        allow(Bundler.settings).to receive(:[]).and_call_original
        allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(4)

        expect(Bundler::ParallelInstaller).to receive(:call).with(
          subject, specs, 4, nil, nil, local: nil
        ).and_return([])

        subject.run({})
        expect(subject.post_install_messages).to eq({})
      end
    end

    context "when jobs setting is not configured" do
      it "falls back to processor count from settings" do
        allow(Bundler.settings).to receive(:[]).and_call_original
        allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(nil)
        allow(Bundler.settings).to receive(:processor_count).and_return(2)

        expect(Bundler::ParallelInstaller).to receive(:call).with(
          subject, specs, 2, nil, nil, local: nil
        ).and_return([])

        subject.run({})
        expect(subject.post_install_messages).to eq({})
      end
    end

    it "passes standalone option through to ParallelInstaller" do
      allow(Bundler.settings).to receive(:[]).and_call_original
      allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(1)
      allow(Bundler::Standalone).to receive(:new).and_return(double(generate: nil))

      expect(Bundler::ParallelInstaller).to receive(:call).with(
        subject, specs, 1, true, nil, local: nil
      ).and_return([])

      subject.run(standalone: true)
      expect(subject.post_install_messages).to eq({})
    end

    it "passes force option through to ParallelInstaller" do
      allow(Bundler.settings).to receive(:[]).and_call_original
      allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(1)

      expect(Bundler::ParallelInstaller).to receive(:call).with(
        subject, specs, 1, nil, true, local: nil
      ).and_return([])

      subject.run(force: true)
      expect(subject.post_install_messages).to eq({})
    end

    it "passes local option through to ParallelInstaller" do
      allow(Bundler.settings).to receive(:[]).and_call_original
      allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(1)

      expect(Bundler::ParallelInstaller).to receive(:call).with(
        subject, specs, 1, nil, nil, local: true
      ).and_return([])

      subject.run(local: true)
      expect(subject.post_install_messages).to eq({})
    end

    it "maps prefer-local option to local parameter in ParallelInstaller" do
      allow(Bundler.settings).to receive(:[]).and_call_original
      allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(1)

      expect(Bundler::ParallelInstaller).to receive(:call).with(
        subject, specs, 1, nil, nil, local: true
      ).and_return([])

      subject.run("prefer-local": true)
      expect(subject.post_install_messages).to eq({})
    end
  end

  # ---------------------------------------------------------------------------
  # attribute accessors
  # ---------------------------------------------------------------------------
  describe "attribute accessors" do
    subject { described_class.new(root, definition) }

    it "exposes post_install_messages via attr_reader as a Hash" do
      expect(subject).to respond_to(:post_install_messages)
      expect(subject.post_install_messages).to eq({})
    end

    it "exposes definition via attr_reader matching the constructor argument" do
      expect(subject).to respond_to(:definition)
      expect(subject.definition).to eq(definition)
    end
  end
end
