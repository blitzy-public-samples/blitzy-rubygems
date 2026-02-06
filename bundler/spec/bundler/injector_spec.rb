# frozen_string_literal: true

require "spec_helper"
require "bundler/injector"

RSpec.describe Bundler::Injector do
  describe "INJECTED_GEMS" do
    it "is defined as a string constant with the expected value" do
      expect(described_class::INJECTED_GEMS).to eq("injected gems")
      expect(described_class::INJECTED_GEMS).to be_a(String)
    end
  end

  describe "#initialize" do
    it "accepts a deps array and exposes inject and remove methods" do
      deps = [Bundler::Dependency.new("testgem", ">= 0")]
      injector = described_class.new(deps)

      expect(injector).to be_a(described_class)
      expect(injector).to respond_to(:inject)
      expect(injector).to respond_to(:remove)
    end

    it "accepts a deps array with a custom options hash" do
      deps = [Bundler::Dependency.new("testgem", ">= 0")]
      options = { conservative_versioning: true, strict: false }
      injector = described_class.new(deps, options)

      expect(injector).to be_a(described_class)
      expect(injector).to respond_to(:inject)
    end

    it "accepts an empty deps array without error" do
      injector = described_class.new([])

      expect(injector).to be_a(described_class)
      expect(injector).to respond_to(:inject)
      expect(injector).to respond_to(:remove)
    end
  end

  describe ".inject" do
    let(:gemfile_path) { bundled_app_gemfile }
    let(:lockfile_path) { bundled_app_lock }
    let(:new_dep) { Bundler::Dependency.new("newgem", ">= 1.0") }

    let(:definition) do
      instance_double("Bundler::Definition",
        remotely!: nil,
        lock: nil,
        specs: { "newgem" => [double("spec", version: Gem::Version.new("1.2.3"))] })
    end

    let(:builder) do
      instance_double("Bundler::Dsl",
        dependencies: [],
        eval_gemfile: nil,
        to_definition: definition)
    end

    let(:bundler_definition) do
      instance_double("Bundler::Definition",
        ensure_equivalent_gemfile_and_lockfile: nil)
    end

    before do
      allow(Bundler).to receive(:default_gemfile).and_return(gemfile_path)
      allow(Bundler).to receive(:default_lockfile).and_return(lockfile_path)
      allow(Bundler).to receive(:definition).and_return(bundler_definition)
      allow(Bundler.settings).to receive(:temporary).and_yield
      allow(Bundler::Dsl).to receive(:new).and_return(builder)
      allow(Bundler).to receive(:reset_paths!)
      FileUtils.mkdir_p(File.dirname(gemfile_path))
      File.write(gemfile_path, "source 'https://rubygems.org'\n")
    end

    it "creates a new Injector and returns the result of inject with default paths" do
      result = described_class.inject([new_dep])

      expect(result).to be_an(Array)
      expect(result.map(&:name)).to include("newgem")
    end

    it "uses Bundler.default_gemfile and Bundler.default_lockfile for file paths" do
      described_class.inject([new_dep])

      expect(Bundler).to have_received(:default_gemfile)
      expect(Bundler).to have_received(:default_lockfile)
    end

    it "passes options through to the underlying Injector instance" do
      spec_double = double("spec", version: Gem::Version.new("2.3.4"))
      allow(definition).to receive(:specs).and_return({ "newgem" => [spec_double] })

      result = described_class.inject([new_dep], conservative_versioning: true)

      expect(result).to be_an(Array)
      expect(result.map(&:name)).to include("newgem")
    end
  end

  describe ".remove" do
    let(:gemfile_path) { bundled_app_gemfile }
    let(:lockfile_path) { bundled_app_lock }
    let(:dep_to_remove) { Bundler::Dependency.new("removeme", ">= 1.0") }

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
      allow(Bundler).to receive(:default_gemfile).and_return(gemfile_path)
      allow(Bundler).to receive(:default_lockfile).and_return(lockfile_path)
      allow(Bundler).to receive(:definition).and_return(definition)
      allow(Bundler).to receive(:ui).and_return(mock_ui)
      allow(Bundler).to receive(:reset_paths!)
      FileUtils.mkdir_p(File.dirname(gemfile_path))
    end

    it "creates a new Injector and invokes remove with default gemfile and lockfile" do
      File.write(gemfile_path, "source 'https://rubygems.org'\ngem \"removeme\", \">= 1.0\"\n")
      deps_list = [dep_to_remove]

      builder1 = instance_double("Bundler::Dsl")
      builder2 = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder1, builder2)
      allow(builder1).to receive(:eval_gemfile)
      allow(builder1).to receive(:dependencies).and_return(deps_list)
      allow(builder2).to receive(:eval_gemfile)
      allow(builder2).to receive(:dependencies).and_return([])
      allow(Bundler::SharedHelpers).to receive(:write_to_gemfile)

      described_class.remove(["removeme"])

      expect(Bundler).to have_received(:default_gemfile)
      expect(Bundler).to have_received(:default_lockfile)
    end

    it "delegates to remove and resets paths after completion" do
      File.write(gemfile_path, "source 'https://rubygems.org'\ngem \"removeme\"\n")
      deps_list = [dep_to_remove]

      builder1 = instance_double("Bundler::Dsl")
      builder2 = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder1, builder2)
      allow(builder1).to receive(:eval_gemfile)
      allow(builder1).to receive(:dependencies).and_return(deps_list)
      allow(builder2).to receive(:eval_gemfile)
      allow(builder2).to receive(:dependencies).and_return([])
      allow(Bundler::SharedHelpers).to receive(:write_to_gemfile)

      described_class.remove(["removeme"])

      expect(Bundler).to have_received(:reset_paths!)
      expect(mock_ui).to have_received(:confirm).with(/removeme.*was removed/)
    end
  end

  describe "#inject" do
    let(:gemfile_path) { bundled_app_gemfile }
    let(:lockfile_path) { bundled_app_lock }
    let(:new_dep) { Bundler::Dependency.new("newgem", ">= 1.0") }
    let(:existing_dep) { Bundler::Dependency.new("existinggem", ">= 2.0") }

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
      FileUtils.mkdir_p(File.dirname(gemfile_path))
      File.write(gemfile_path, "source 'https://rubygems.org'\n")
    end

    it "calls ensure_equivalent_gemfile_and_lockfile on the current definition" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      expect(bundler_definition).to have_received(:ensure_equivalent_gemfile_and_lockfile).with(true)
      expect(Bundler).to have_received(:definition)
    end

    it "temporarily unfreezes deployment and frozen settings during injection" do
      expect(Bundler.settings).to receive(:temporary).with(deployment: false, frozen: false).and_yield

      injector = described_class.new([new_dep])
      result = injector.inject(gemfile_path, lockfile_path)

      expect(result).to be_an(Array)
    end

    it "evaluates the existing Gemfile through the Dsl builder" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      expect(builder).to have_received(:eval_gemfile).with(gemfile_path)
      expect(Bundler::Dsl).to have_received(:new)
    end

    it "removes already-existing dependencies from the injection list" do
      injector = described_class.new([existing_dep])
      result = injector.inject(gemfile_path, lockfile_path)

      expect(result).to be_empty
      expect(result).to be_an(Array)
    end

    it "evaluates injected gem lines when new deps remain after deduplication" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      expect(builder).to have_received(:eval_gemfile).with(described_class::INJECTED_GEMS, anything)
      expect(builder).to have_received(:to_definition).with(lockfile_path, {})
    end

    it "resolves the definition remotely and writes the lockfile" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      expect(definition).to have_received(:remotely!)
      expect(definition).to have_received(:lock)
    end

    it "appends gem lines to the Gemfile when new dependencies exist" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      gemfile_content = File.read(gemfile_path)
      expect(gemfile_content).to include("gem \"newgem\"")
      expect(gemfile_content).to include("source 'https://rubygems.org'")
    end

    it "invalidates the cached Bundler definition by calling reset_paths!" do
      injector = described_class.new([new_dep])
      injector.inject(gemfile_path, lockfile_path)

      expect(Bundler).to have_received(:reset_paths!)
      expect(definition).to have_received(:lock)
    end

    it "returns the array of newly added dependencies" do
      injector = described_class.new([new_dep])
      result = injector.inject(gemfile_path, lockfile_path)

      expect(result).to be_an(Array)
      expect(result.map(&:name)).to include("newgem")
    end

    context "when all deps already exist in the Gemfile" do
      it "returns an empty array and does not evaluate injected gems" do
        injector = described_class.new([existing_dep])
        result = injector.inject(gemfile_path, lockfile_path)

        expect(result).to be_empty
        expect(builder).not_to have_received(:eval_gemfile).with(described_class::INJECTED_GEMS, anything)
      end
    end

    context "with conservative versioning option" do
      it "appends gem lines using pessimistic version constraints" do
        spec_double = double("spec", version: Gem::Version.new("2.3.4"))
        allow(definition).to receive(:specs).and_return({ "newgem" => [spec_double] })

        injector = described_class.new([new_dep], conservative_versioning: true)
        injector.inject(gemfile_path, lockfile_path)

        gemfile_content = File.read(gemfile_path)
        expect(gemfile_content).to include("gem \"newgem\"")
        expect(gemfile_content).to include("~>")
      end
    end
  end

  describe "#remove" do
    let(:gemfile_path) { bundled_app_gemfile }
    let(:lockfile_path) { bundled_app_lock }
    let(:dep_to_remove) { Bundler::Dependency.new("removeme", ">= 1.0") }

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

    it "iterates over all gemfiles returned by the definition" do
      File.write(gemfile_path, "source 'https://rubygems.org'\ngem \"removeme\", \">= 1.0\"\n")
      deps_list = [dep_to_remove]

      builder1 = instance_double("Bundler::Dsl")
      builder2 = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder1, builder2)
      allow(builder1).to receive(:eval_gemfile)
      allow(builder1).to receive(:dependencies).and_return(deps_list)
      allow(builder2).to receive(:eval_gemfile)
      allow(builder2).to receive(:dependencies).and_return([])
      allow(Bundler::SharedHelpers).to receive(:write_to_gemfile)

      injector = described_class.new(["removeme"])
      injector.remove(gemfile_path, lockfile_path)

      expect(definition).to have_received(:gemfiles)
      expect(Bundler).to have_received(:reset_paths!)
    end

    it "invalidates the cached Bundler definition after removal" do
      File.write(gemfile_path, "source 'https://rubygems.org'\ngem \"removeme\"\n")
      deps_list = [dep_to_remove]

      builder1 = instance_double("Bundler::Dsl")
      builder2 = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder1, builder2)
      allow(builder1).to receive(:eval_gemfile)
      allow(builder1).to receive(:dependencies).and_return(deps_list)
      allow(builder2).to receive(:eval_gemfile)
      allow(builder2).to receive(:dependencies).and_return([])
      allow(Bundler::SharedHelpers).to receive(:write_to_gemfile)

      injector = described_class.new(["removeme"])
      injector.remove(gemfile_path, lockfile_path)

      expect(Bundler).to have_received(:reset_paths!)
      expect(mock_ui).to have_received(:confirm).with(/removeme.*was removed/)
    end

    it "raises GemfileError when the gem is not found in the Gemfile" do
      File.write(gemfile_path, "source 'https://rubygems.org'\n")

      builder = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder)
      allow(builder).to receive(:eval_gemfile)
      allow(builder).to receive(:dependencies).and_return([])

      injector = described_class.new(["nonexistent"])

      expect {
        injector.remove(gemfile_path, lockfile_path)
      }.to raise_error(Bundler::GemfileError, /is not specified in/)
      expect(mock_ui).to have_received(:info).with(/Removing gems from/)
    end

    it "confirms removal for each successfully removed dependency" do
      File.write(gemfile_path, "source 'https://rubygems.org'\ngem \"removeme\"\n")
      deps_list = [dep_to_remove]

      builder1 = instance_double("Bundler::Dsl")
      builder2 = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder1, builder2)
      allow(builder1).to receive(:eval_gemfile)
      allow(builder1).to receive(:dependencies).and_return(deps_list)
      allow(builder2).to receive(:eval_gemfile)
      allow(builder2).to receive(:dependencies).and_return([])
      allow(Bundler::SharedHelpers).to receive(:write_to_gemfile)

      injector = described_class.new(["removeme"])
      injector.remove(gemfile_path, lockfile_path)

      expect(mock_ui).to have_received(:confirm).with(/removeme.*was removed/)
      expect(mock_ui).to have_received(:info).with(/Removing gems from/)
    end

    it "writes the cleaned gemfile content via SharedHelpers.write_to_gemfile" do
      File.write(gemfile_path, "source 'https://rubygems.org'\ngem \"removeme\"\n")
      deps_list = [dep_to_remove]

      builder1 = instance_double("Bundler::Dsl")
      builder2 = instance_double("Bundler::Dsl")
      allow(Bundler::Dsl).to receive(:new).and_return(builder1, builder2)
      allow(builder1).to receive(:eval_gemfile)
      allow(builder1).to receive(:dependencies).and_return(deps_list)
      allow(builder2).to receive(:eval_gemfile)
      allow(builder2).to receive(:dependencies).and_return([])
      allow(Bundler::SharedHelpers).to receive(:write_to_gemfile)

      injector = described_class.new(["removeme"])
      injector.remove(gemfile_path, lockfile_path)

      expect(Bundler::SharedHelpers).to have_received(:write_to_gemfile).with(gemfile_path, anything)
      expect(definition).to have_received(:gemfiles)
    end
  end

  context "dependency management" do
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
      allow(builder).to receive(:dependencies).and_return([existing])

      spec_new = double("spec", version: Gem::Version.new("1.0.0"))
      definition = instance_double("Bundler::Definition",
        remotely!: nil,
        lock: nil,
        specs: { "brandnew" => [spec_new] })
      allow(builder).to receive(:to_definition).and_return(definition)

      injector = described_class.new([existing, new_gem])
      result = injector.inject(gemfile_path, lockfile_path)

      expect(result.map(&:name)).to include("brandnew")
      expect(result.map(&:name)).not_to include("existing")
    end

    it "injects multiple new dependencies at once" do
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
      expect(result).to be_an(Array)
    end
  end
end
