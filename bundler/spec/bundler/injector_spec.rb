# frozen_string_literal: true

require "spec_helper"
require "bundler/injector"

RSpec.describe Bundler::Injector do
  describe "INJECTED_GEMS" do
    it "is defined as a string constant" do
      expect(described_class::INJECTED_GEMS).to eq("injected gems")
      expect(described_class::INJECTED_GEMS).to be_a(String)
    end
  end

  describe "#initialize" do
    it "accepts a deps array and empty options hash by default" do
      deps = [double("dep")]
      injector = described_class.new(deps)
      expect(injector).to be_a(described_class)
      expect(injector).to respond_to(:inject)
      expect(injector).to respond_to(:remove)
    end

    it "accepts a deps array and a custom options hash" do
      deps = [double("dep")]
      options = { conservative_versioning: true, strict: false }
      injector = described_class.new(deps, options)
      expect(injector).to be_a(described_class)
    end
  end

  describe ".inject" do
    it "creates an Injector and delegates to #inject with default gemfile and lockfile paths" do
      deps = [double("dep")]
      options = { conservative_versioning: true }
      gemfile_path = Pathname.new("/tmp/Gemfile")
      lockfile_path = Pathname.new("/tmp/Gemfile.lock")

      allow(Bundler).to receive(:default_gemfile).and_return(gemfile_path)
      allow(Bundler).to receive(:default_lockfile).and_return(lockfile_path)

      injector_instance = instance_double(described_class)
      allow(described_class).to receive(:new).with(deps, options).and_return(injector_instance)
      allow(injector_instance).to receive(:inject).with(gemfile_path, lockfile_path).and_return(deps)

      result = described_class.inject(deps, options)

      expect(described_class).to have_received(:new).with(deps, options)
      expect(injector_instance).to have_received(:inject).with(gemfile_path, lockfile_path)
      expect(result).to eq(deps)
    end

    it "passes empty options hash when none provided" do
      deps = [double("dep")]
      gemfile_path = Pathname.new("/tmp/Gemfile")
      lockfile_path = Pathname.new("/tmp/Gemfile.lock")

      allow(Bundler).to receive(:default_gemfile).and_return(gemfile_path)
      allow(Bundler).to receive(:default_lockfile).and_return(lockfile_path)

      injector_instance = instance_double(described_class)
      allow(described_class).to receive(:new).with(deps, {}).and_return(injector_instance)
      allow(injector_instance).to receive(:inject).with(gemfile_path, lockfile_path).and_return(deps)

      described_class.inject(deps)

      expect(described_class).to have_received(:new).with(deps, {})
    end
  end

  describe ".remove" do
    it "creates an Injector and delegates to #remove with default gemfile and lockfile paths" do
      gems = ["foo", "bar"]
      options = { force: true }
      gemfile_path = Pathname.new("/tmp/Gemfile")
      lockfile_path = Pathname.new("/tmp/Gemfile.lock")

      allow(Bundler).to receive(:default_gemfile).and_return(gemfile_path)
      allow(Bundler).to receive(:default_lockfile).and_return(lockfile_path)

      injector_instance = instance_double(described_class)
      allow(described_class).to receive(:new).with(gems, options).and_return(injector_instance)
      allow(injector_instance).to receive(:remove).with(gemfile_path, lockfile_path)

      described_class.remove(gems, options)

      expect(described_class).to have_received(:new).with(gems, options)
      expect(injector_instance).to have_received(:remove).with(gemfile_path, lockfile_path)
    end

    it "passes empty options hash when none provided" do
      gems = ["baz"]
      gemfile_path = Pathname.new("/tmp/Gemfile")
      lockfile_path = Pathname.new("/tmp/Gemfile.lock")

      allow(Bundler).to receive(:default_gemfile).and_return(gemfile_path)
      allow(Bundler).to receive(:default_lockfile).and_return(lockfile_path)

      injector_instance = instance_double(described_class)
      allow(described_class).to receive(:new).with(gems, {}).and_return(injector_instance)
      allow(injector_instance).to receive(:remove).with(gemfile_path, lockfile_path)

      described_class.remove(gems)

      expect(described_class).to have_received(:new).with(gems, {})
    end
  end

  describe "#inject" do
    let(:gemfile_path) { bundled_app_gemfile }
    let(:lockfile_path) { bundled_app_lock }
    let(:new_dep) do
      Bundler::Dependency.new("newgem", ">= 1.0")
    end
    let(:existing_dep) do
      Bundler::Dependency.new("existinggem", ">= 2.0")
    end

    let(:definition) do
      instance_double("Bundler::Definition",
        remotely!: nil,
        lock: nil,
        specs: { "newgem" => [double("spec", version: Gem::Version.new("1.2.3"))] })
    end

    let(:builder) do
      instance_double("Bundler::Dsl",
        dependencies: [existing_dep],
        eval_gemfile: nil,
        to_definition: definition)
    end

    let(:bundler_definition) do
      instance_double("Bundler::Definition",
        ensure_equivalent_gemfile_and_lockfile: nil)
    end

    before do
      allow(Bundler).to receive(:definition).and_return(bundler_definition)
      allow(Bundler.settings).to receive(:temporary).and_yield
      allow(Bundler::Dsl).to receive(:new).and_return(builder)
      allow(Bundler).to receive(:reset_paths!)
      # Ensure the gemfile_path exists and is writable for append_to
      FileUtils.mkdir_p(File.dirname(gemfile_path))
      File.write(gemfile_path, "source 'https://rubygems.org'\n")
    end

    it "calls ensure_equivalent_gemfile_and_lockfile on the current definition" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      expect(bundler_definition).to have_received(:ensure_equivalent_gemfile_and_lockfile).with(true)
    end

    it "temporarily unfreezes settings during injection" do
      expect(Bundler.settings).to receive(:temporary).with(deployment: false, frozen: false).and_yield

      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)
    end

    it "evaluates the existing Gemfile via Dsl" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      expect(builder).to have_received(:eval_gemfile).with(gemfile_path)
    end

    it "removes already-existing dependencies from the injection list" do
      # Inject a dep that already exists in builder.dependencies
      injector = described_class.new([existing_dep])
      result = injector.inject(gemfile_path, lockfile_path)

      # The dep was removed because it already existed, so result is empty
      expect(result).to be_empty
    end

    it "evaluates injected gem lines when new deps remain after deduplication" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      # builder.eval_gemfile is called twice: once for the gemfile_path and once for INJECTED_GEMS
      expect(builder).to have_received(:eval_gemfile).with(described_class::INJECTED_GEMS, anything)
    end

    it "creates a definition from the builder and resolves remotely" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      expect(builder).to have_received(:to_definition).with(lockfile_path, {})
      expect(definition).to have_received(:remotely!)
    end

    it "appends gem lines to the Gemfile when new deps exist" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      gemfile_content = File.read(gemfile_path)
      expect(gemfile_content).to include("gem \"newgem\"")
    end

    it "locks the definition after successful resolution" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      expect(definition).to have_received(:lock)
    end

    it "invalidates cached Bundler definition by calling reset_paths!" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      expect(Bundler).to have_received(:reset_paths!)
    end

    it "returns the array of newly added dependencies" do
      injector = described_class.new([new_dep])
      result = injector.inject(gemfile_path, lockfile_path)

      expect(result).to be_an(Array)
      expect(result.map(&:name)).to include("newgem")
    end

    context "when all deps already exist in the Gemfile" do
      it "returns an empty array and does not modify the Gemfile" do
        injector = described_class.new([existing_dep])
        result = injector.inject(gemfile_path, lockfile_path)

        expect(result).to be_empty
        # eval_gemfile should only be called once (for the existing Gemfile), not for INJECTED_GEMS
        expect(builder).not_to have_received(:eval_gemfile).with(described_class::INJECTED_GEMS, anything)
      end
    end

    context "with conservative versioning option" do
      it "appends gem lines using conservative version constraints" do
        spec_double = double("spec", version: Gem::Version.new("2.3.4"))
        allow(definition).to receive(:specs).and_return({ "newgem" => [spec_double] })

        injector = described_class.new([new_dep], conservative_versioning: true)
        injector.inject(gemfile_path, lockfile_path)

        gemfile_content = File.read(gemfile_path)
        # With conservative versioning, the version should use pessimistic constraint
        expect(gemfile_content).to include("gem \"newgem\"")
        expect(gemfile_content).to include("~>")
      end
    end
  end

  describe "#remove" do
    let(:gemfile_path) { bundled_app_gemfile }
    let(:lockfile_path) { bundled_app_lock }

    let(:dep_to_remove) do
      dep = Bundler::Dependency.new("removeme", ">= 1.0")
      dep
    end

    let(:mock_ui) do
      ui = double("ui")
      allow(ui).to receive(:info)
      allow(ui).to receive(:confirm)
      allow(ui).to receive(:add_color) { |msg, _color| msg }
      ui
    end

    let(:definition) do
      instance_double("Bundler::Definition",
        gemfiles: [gemfile_path])
    end

    before do
      allow(Bundler).to receive(:definition).and_return(definition)
      allow(Bundler).to receive(:ui).and_return(mock_ui)
      allow(Bundler).to receive(:reset_paths!)
      FileUtils.mkdir_p(File.dirname(gemfile_path))
    end

    it "iterates over all gemfiles from the definition" do
      File.write(gemfile_path, "source 'https://rubygems.org'\ngem \"removeme\", \">= 1.0\"\n")

      # Build a fresh DSL builder that actually knows about the dep
      builder = Bundler::Dsl.new
      allow(Bundler::Dsl).to receive(:new).and_return(builder)
      allow(builder).to receive(:eval_gemfile).and_call_original

      # For the first eval_gemfile the builder parses the Gemfile and discovers "removeme"
      # For the cross_check eval, the builder parses the cleaned Gemfile
      allow(builder).to receive(:eval_gemfile) do |path|
        # Return the builder so the dependencies list stays current
      end
      allow(builder).to receive(:dependencies).and_return([dep_to_remove], [])
      allow(Bundler::SharedHelpers).to receive(:write_to_gemfile)
      allow(File).to receive(:readlines).with(gemfile_path).and_return(
        ["source 'https://rubygems.org'\n", "gem \"removeme\", \">= 1.0\"\n"]
      )

      injector = described_class.new(["removeme"])
      injector.remove(gemfile_path, lockfile_path)

      expect(definition).to have_received(:gemfiles)
    end

    it "invalidates cached Bundler definition after removal" do
      File.write(gemfile_path, "source 'https://rubygems.org'\ngem \"removeme\"\n")

      builder = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder)
      allow(builder).to receive(:eval_gemfile)
      allow(builder).to receive(:dependencies).and_return([dep_to_remove], [])
      allow(Bundler::SharedHelpers).to receive(:write_to_gemfile)
      allow(File).to receive(:readlines).with(gemfile_path).and_return(
        ["source 'https://rubygems.org'\n", "gem \"removeme\"\n"]
      )

      injector = described_class.new(["removeme"])
      injector.remove(gemfile_path, lockfile_path)

      expect(Bundler).to have_received(:reset_paths!)
    end

    it "shows a warning when no gems were removed" do
      File.write(gemfile_path, "source 'https://rubygems.org'\n")

      builder = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder)
      allow(builder).to receive(:eval_gemfile)
      allow(builder).to receive(:dependencies).and_return([])

      # When the gem is not found in the Gemfile, it raises GemfileError
      injector = described_class.new(["nonexistent"])
      expect {
        injector.remove(gemfile_path, lockfile_path)
      }.to raise_error(Bundler::GemfileError, /is not specified in/)
    end

    it "confirms removal for each successfully removed dependency" do
      File.write(gemfile_path, "source 'https://rubygems.org'\ngem \"removeme\"\n")

      builder = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder)
      allow(builder).to receive(:eval_gemfile)
      allow(builder).to receive(:dependencies).and_return([dep_to_remove], [])
      allow(Bundler::SharedHelpers).to receive(:write_to_gemfile)
      allow(File).to receive(:readlines).with(gemfile_path).and_return(
        ["source 'https://rubygems.org'\n", "gem \"removeme\"\n"]
      )

      injector = described_class.new(["removeme"])
      injector.remove(gemfile_path, lockfile_path)

      expect(mock_ui).to have_received(:confirm).with(/removeme.*was removed/)
    end
  end

  describe "dependency management" do
    let(:gemfile_path) { bundled_app_gemfile }
    let(:lockfile_path) { bundled_app_lock }

    let(:bundler_definition) do
      instance_double("Bundler::Definition",
        ensure_equivalent_gemfile_and_lockfile: nil)
    end

    before do
      allow(Bundler).to receive(:definition).and_return(bundler_definition)
      allow(Bundler.settings).to receive(:temporary).and_yield
      allow(Bundler).to receive(:reset_paths!)
      FileUtils.mkdir_p(File.dirname(gemfile_path))
      File.write(gemfile_path, "source 'https://rubygems.org'\ngem \"existing\"\n")
    end

    it "does not inject gems that are already present in the Gemfile" do
      existing = Bundler::Dependency.new("existing", ">= 0")
      new_gem = Bundler::Dependency.new("brandnew", ">= 1.0")

      builder = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder)
      allow(builder).to receive(:eval_gemfile)
      # The builder returns a dependency matching "existing"
      allow(builder).to receive(:dependencies).and_return([existing])

      definition = instance_double("Bundler::Definition",
        remotely!: nil,
        lock: nil,
        specs: { "brandnew" => [double("spec", version: Gem::Version.new("1.0.0"))] })
      allow(builder).to receive(:to_definition).and_return(definition)

      injector = described_class.new([existing, new_gem])
      result = injector.inject(gemfile_path, lockfile_path)

      # Only the brand new gem should be in the result, not the existing one
      expect(result.map(&:name)).to include("brandnew")
      expect(result.map(&:name)).not_to include("existing")
    end

    it "handles injection of multiple new dependencies at once" do
      dep1 = Bundler::Dependency.new("gem_a", ">= 1.0")
      dep2 = Bundler::Dependency.new("gem_b", ">= 2.0")

      builder = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder)
      allow(builder).to receive(:eval_gemfile)
      allow(builder).to receive(:dependencies).and_return([])

      spec_a = double("spec_a", version: Gem::Version.new("1.0.0"))
      spec_b = double("spec_b", version: Gem::Version.new("2.0.0"))
      definition = instance_double("Bundler::Definition",
        remotely!: nil,
        lock: nil,
        specs: { "gem_a" => [spec_a], "gem_b" => [spec_b] })
      allow(builder).to receive(:to_definition).and_return(definition)

      injector = described_class.new([dep1, dep2])
      result = injector.inject(gemfile_path, lockfile_path)

      expect(result.length).to eq(2)
      expect(result.map(&:name)).to contain_exactly("gem_a", "gem_b")
    end

    it "returns empty array when all injected deps already exist" do
      existing = Bundler::Dependency.new("existing", ">= 0")

      builder = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder)
      allow(builder).to receive(:eval_gemfile)
      allow(builder).to receive(:dependencies).and_return([existing])

      definition = instance_double("Bundler::Definition",
        remotely!: nil,
        lock: nil,
        specs: {})
      allow(builder).to receive(:to_definition).and_return(definition)

      injector = described_class.new([existing])
      result = injector.inject(gemfile_path, lockfile_path)

      expect(result).to be_empty
    end
  end
end
