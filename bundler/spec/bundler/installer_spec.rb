# frozen_string_literal: true

require "spec_helper"
require "bundler/installer"
require "bundler/plugin/events"

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
  let(:dependencies) { [double("dep1", name: "rake"), double("dep2", name: "rspec")] }
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

  describe ".install" do
    it "creates an Installer instance and invokes run" do
      allow(Bundler::Plugin).to receive(:hook)
      allow(Bundler::ProcessLock).to receive(:lock).and_yield
      allow(Bundler).to receive(:create_bundle_path)
      allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
      allow(definition).to receive(:setup_domain!).and_return(false)
      allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
      allow(Gem::Specification).to receive(:reset)

      result = described_class.install(root, definition, {})

      expect(result).to be_a(described_class)
    end

    it "fires GEM_BEFORE_INSTALL_ALL plugin hook before run" do
      allow(Bundler::ProcessLock).to receive(:lock).and_yield
      allow(Bundler).to receive(:create_bundle_path)
      allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
      allow(definition).to receive(:setup_domain!).and_return(false)
      allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
      allow(Gem::Specification).to receive(:reset)

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

    it "fires GEM_AFTER_INSTALL_ALL plugin hook after run" do
      allow(Bundler::ProcessLock).to receive(:lock).and_yield
      allow(Bundler).to receive(:create_bundle_path)
      allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
      allow(definition).to receive(:setup_domain!).and_return(false)
      allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
      allow(Gem::Specification).to receive(:reset)
      allow(Bundler::Plugin).to receive(:hook)

      expect(Bundler::Plugin).to receive(:hook).with(
        Bundler::Plugin::Events::GEM_AFTER_INSTALL_ALL,
        dependencies
      )

      described_class.install(root, definition, {})
    end

    it "returns the installer instance with accessible post_install_messages" do
      allow(Bundler::Plugin).to receive(:hook)
      allow(Bundler::ProcessLock).to receive(:lock).and_yield
      allow(Bundler).to receive(:create_bundle_path)
      allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
      allow(definition).to receive(:setup_domain!).and_return(false)
      allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
      allow(Gem::Specification).to receive(:reset)

      installer = described_class.install(root, definition, {})

      expect(installer.post_install_messages).to be_a(Hash)
      expect(installer.definition).to eq(definition)
    end
  end

  describe "#initialize" do
    subject { described_class.new(root, definition) }

    it "sets up the definition accessor" do
      expect(subject.definition).to eq(definition)
    end

    it "initializes post_install_messages as an empty hash" do
      expect(subject.post_install_messages).to eq({})
    end
  end

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

      it "warns about empty Gemfile and returns early" do
        allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)

        expect(Bundler.ui).to receive(:warn).with("The Gemfile specifies no dependencies")
        expect(definition).to receive(:lock)

        subject.run({})
      end

      it "does not invoke the install process" do
        allow(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
        allow(Bundler.ui).to receive(:warn)
        allow(definition).to receive(:lock)

        expect(Bundler::ParallelInstaller).not_to receive(:call)

        subject.run({})
      end
    end

    context "when dependencies exist" do
      it "calls create_bundle_path" do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])

        expect(Bundler).to receive(:create_bundle_path)

        subject.run({})
      end

      it "acquires a ProcessLock" do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])

        expect(Bundler::ProcessLock).to receive(:lock).and_yield

        subject.run({})
      end

      it "ensures gemfile and lockfile equivalence" do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])

        expect(definition).to receive(:ensure_equivalent_gemfile_and_lockfile).with(nil)

        subject.run({})
      end

      it "passes deployment flag to ensure_equivalent_gemfile_and_lockfile" do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])

        expect(definition).to receive(:ensure_equivalent_gemfile_and_lockfile).with(true)

        subject.run(deployment: true)
      end

      it "resets Gem::Specification cache after install" do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])

        expect(Gem::Specification).to receive(:reset)

        subject.run({})
      end

      it "locks the definition after install" do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])

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

      it "checks spec compatibility without error for compatible specs" do
        expect { subject.run({}) }.not_to raise_error
      end

      it "loads plugins" do
        expect(Gem).to receive(:load_plugins)

        subject.run({})
      end
    end

    context "when setup_domain! returns false" do
      it "does not check spec compatibility or load plugins" do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])

        expect(Gem).not_to receive(:load_plugins)

        subject.run({})
      end
    end

    context "when standalone option is specified" do
      let(:standalone_instance) { double("Standalone", generate: nil) }

      it "generates standalone setup" do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])

        expect(Bundler::Standalone).to receive(:new).with(true, definition).and_return(standalone_instance)
        expect(standalone_instance).to receive(:generate)

        subject.run(standalone: true)
      end
    end

    context "when standalone option is falsy" do
      it "does not generate standalone setup" do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])

        expect(Bundler::Standalone).not_to receive(:new)

        subject.run({})
      end
    end

    context "when specs have post-install messages" do
      let(:installation) do
        double("Installation",
          name: "rake",
          has_post_install_message?: true,
          post_install_message: "Thanks for installing rake!")
      end

      it "collects post_install_messages from installations" do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([installation])

        subject.run({})

        expect(subject.post_install_messages).to eq("rake" => "Thanks for installing rake!")
      end
    end

    context "when specs do not have post-install messages" do
      let(:installation) do
        double("Installation",
          name: "rake",
          has_post_install_message?: false)
      end

      it "does not add to post_install_messages" do
        allow(definition).to receive(:setup_domain!).and_return(false)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([installation])

        subject.run({})

        expect(subject.post_install_messages).to eq({})
      end
    end
  end

  describe "#generate_bundler_executable_stubs" do
    subject { described_class.new(root, definition) }

    context "when spec is for bundler itself" do
      let(:bundler_spec) { double("Spec", name: "bundler") }

      it "warns and returns without generating stubs" do
        expect(Bundler.ui).to receive(:warn).with(
          "Bundler itself does not use binstubs because its version is selected by RubyGems"
        )

        subject.generate_bundler_executable_stubs(bundler_spec)
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

        it "warns about executables in dependent gems" do
          expect(Bundler.ui).to receive(:warn).with(
            "activesupport has no executables, but you may want one from a gem it depends on."
          )
          expect(Bundler.ui).to receive(:warn).with("  railties has: rails")

          subject.generate_bundler_executable_stubs(spec_without_executables, binstubs_cmd: true)
        end
      end

      context "when runtime dependencies have no executables" do
        let(:dep_spec) { double("DepSpec", executables: []) }
        let(:dep) { double("Dep", name: "concurrent-ruby") }
        let(:dep_specs) { double("DepSpecs", first: dep_spec) }

        before do
          allow(spec_without_executables).to receive(:runtime_dependencies).and_return([dep])
          allow(definition).to receive(:specs).and_return(double("Specs", :[] => dep_specs))
        end

        it "warns there are no executables at all" do
          expect(Bundler.ui).to receive(:warn).with(
            "There are no executables for the gem activesupport."
          )

          subject.generate_bundler_executable_stubs(spec_without_executables, binstubs_cmd: true)
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

      it "writes binstub files for each executable" do
        subject.generate_bundler_executable_stubs(spec_with_executables, force: true)

        expect(File.exist?(bin_path.join("rake"))).to be true
      end

      it "skips existing binstubs without force option" do
        File.write(bin_path.join("rake"), "existing content")

        subject.generate_bundler_executable_stubs(spec_with_executables)

        expect(File.read(bin_path.join("rake"))).to eq("existing content")
      end

      it "overwrites existing binstubs with force option" do
        File.write(bin_path.join("rake"), "old content")

        subject.generate_bundler_executable_stubs(spec_with_executables, force: true)

        expect(File.read(bin_path.join("rake"))).not_to eq("old content")
      end

      context "with binstubs_cmd and existing stubs" do
        it "warns about skipped stubs for single executable" do
          File.write(bin_path.join("rake"), "existing")

          expect(Bundler.ui).to receive(:warn).with("Skipped rake since it already exists.")
          expect(Bundler.ui).to receive(:warn).with("If you want to overwrite skipped stubs, use --force.")

          subject.generate_bundler_executable_stubs(spec_with_executables, binstubs_cmd: true)
        end
      end

      context "with binstubs_cmd and multiple existing stubs" do
        let(:spec_with_multi_executables) do
          double("Spec",
            name: "rspec",
            executables: ["rspec", "rspec-core"])
        end

        it "warns about skipped stubs for two executables" do
          File.write(bin_path.join("rspec"), "existing")
          File.write(bin_path.join("rspec-core"), "existing")

          expect(Bundler.ui).to receive(:warn).with("Skipped rspec and rspec-core since they already exist.")
          expect(Bundler.ui).to receive(:warn).with("If you want to overwrite skipped stubs, use --force.")

          subject.generate_bundler_executable_stubs(spec_with_multi_executables, binstubs_cmd: true)
        end
      end
    end
  end

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

    it "writes standalone executable stubs" do
      subject.generate_standalone_bundler_executable_stubs(spec)

      expect(File.exist?(standalone_bin_path.join("rake"))).to be true
    end

    it "skips 'bundle' executable" do
      spec_with_bundle = double("Spec",
        name: "bundler",
        executables: ["bundle", "bundler"],
        full_gem_path: standalone_gem_dir.to_s,
        bindir: "bin")

      subject.generate_standalone_bundler_executable_stubs(spec_with_bundle)

      expect(File.exist?(standalone_bin_path.join("bundle"))).to be false
    end

    it "raises error when no explicit path is set" do
      allow(Bundler.settings).to receive(:[]).with(:path).and_return(nil)

      expect { subject.generate_standalone_bundler_executable_stubs(spec) }.to raise_error(
        RuntimeError,
        "Can't standalone without an explicit path set"
      )
    end
  end

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

      it "raises InstallError with Ruby version details" do
        allow(definition).to receive(:setup_domain!).and_return(true)
        allow(Gem).to receive(:load_plugins)
        allow(Gem).to receive(:load_plugin_files)
        allow(Gem).to receive(:load_env_plugins)
        allow(definition).to receive_message_chain(:specs, :select).and_return([])

        expect { subject.run({}) }.to raise_error(
          Bundler::InstallError,
          /some_gem-1.0 requires ruby version >= 99.0/
        )
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

      it "raises InstallError with RubyGems version details" do
        allow(definition).to receive(:setup_domain!).and_return(true)
        allow(Gem).to receive(:load_plugins)
        allow(Gem).to receive(:load_plugin_files)
        allow(Gem).to receive(:load_env_plugins)
        allow(definition).to receive_message_chain(:specs, :select).and_return([])

        expect { subject.run({}) }.to raise_error(
          Bundler::InstallError,
          /another_gem-2.0 requires rubygems version >= 99.0/
        )
      end
    end

    context "when all specs are compatible" do
      it "does not raise any error" do
        allow(definition).to receive(:setup_domain!).and_return(true)
        allow(Bundler::ParallelInstaller).to receive(:call).and_return([])
        allow(Gem).to receive(:load_plugins)
        allow(Gem).to receive(:load_plugin_files)
        allow(Gem).to receive(:load_env_plugins)
        allow(definition).to receive_message_chain(:specs, :select).and_return([])

        expect { subject.run({}) }.not_to raise_error
      end
    end
  end

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
      it "uses the configured number of jobs" do
        allow(Bundler.settings).to receive(:[]).and_call_original
        allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(4)

        expect(Bundler::ParallelInstaller).to receive(:call).with(
          subject, specs, 4, nil, nil, local: nil
        ).and_return([])

        subject.run({})
      end
    end

    context "when jobs setting is not configured" do
      it "falls back to processor count" do
        allow(Bundler.settings).to receive(:[]).and_call_original
        allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(nil)
        allow(Bundler.settings).to receive(:processor_count).and_return(2)

        expect(Bundler::ParallelInstaller).to receive(:call).with(
          subject, specs, 2, nil, nil, local: nil
        ).and_return([])

        subject.run({})
      end
    end

    it "passes standalone option to ParallelInstaller" do
      allow(Bundler.settings).to receive(:[]).and_call_original
      allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(1)
      allow(Bundler::Standalone).to receive(:new).and_return(double(generate: nil))

      expect(Bundler::ParallelInstaller).to receive(:call).with(
        subject, specs, 1, true, nil, local: nil
      ).and_return([])

      subject.run(standalone: true)
    end

    it "passes force option to ParallelInstaller" do
      allow(Bundler.settings).to receive(:[]).and_call_original
      allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(1)

      expect(Bundler::ParallelInstaller).to receive(:call).with(
        subject, specs, 1, nil, true, local: nil
      ).and_return([])

      subject.run(force: true)
    end

    it "passes local option to ParallelInstaller" do
      allow(Bundler.settings).to receive(:[]).and_call_original
      allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(1)

      expect(Bundler::ParallelInstaller).to receive(:call).with(
        subject, specs, 1, nil, nil, local: true
      ).and_return([])

      subject.run(local: true)
    end

    it "passes prefer-local option as local to ParallelInstaller" do
      allow(Bundler.settings).to receive(:[]).and_call_original
      allow(Bundler.settings).to receive(:[]).with(:jobs).and_return(1)

      expect(Bundler::ParallelInstaller).to receive(:call).with(
        subject, specs, 1, nil, nil, local: true
      ).and_return([])

      subject.run("prefer-local": true)
    end
  end

  describe "attribute accessors" do
    subject { described_class.new(root, definition) }

    it "exposes post_install_messages via attr_reader" do
      expect(subject).to respond_to(:post_install_messages)
      expect(subject.post_install_messages).to eq({})
    end

    it "exposes definition via attr_reader" do
      expect(subject).to respond_to(:definition)
      expect(subject.definition).to eq(definition)
    end
  end
end
