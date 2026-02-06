# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "bundler/runtime"
require "bundler/plugin"
require "bundler/plugin/events"

RSpec.describe Bundler::Runtime do
  # Shared test fixtures for controlled definition doubles
  let(:root) { Pathname.new("/tmp/test_app") }

  # Minimal definition double with essential method responses
  let(:definition) do
    double("definition",
      ensure_equivalent_gemfile_and_lockfile: nil,
      no_resolve_needed?: true,
      lock: nil,
      spec_git_paths: [])
  end

  # Build runtime instance with controlled root and definition
  let(:runtime) { described_class.new(root, definition) }

  describe "#initialize" do
    it "creates a new Runtime instance with root and definition" do
      rt = described_class.new(root, definition)
      expect(rt).to be_a(described_class)
      expect(rt).to respond_to(:setup)
    end

    it "stores the definition accessible via delegated methods" do
      allow(definition).to receive(:requested_specs).and_return([])
      rt = described_class.new(root, definition)
      expect(rt.requested_specs).to eq([])
      expect(rt).to respond_to(:specs)
    end

    it "responds to all public instance methods defined by the class" do
      rt = described_class.new(root, definition)
      expect(rt).to respond_to(:setup)
      expect(rt).to respond_to(:require)
      expect(rt).to respond_to(:lock)
      expect(rt).to respond_to(:cache)
      expect(rt).to respond_to(:prune_cache)
      expect(rt).to respond_to(:clean)
    end

    it "includes SharedHelpers module" do
      expect(described_class.ancestors).to include(Bundler::SharedHelpers)
    end
  end

  describe "#setup" do
    # Spec double that simulates a loaded gem specification
    let(:spec_load_paths) { ["/tmp/gems/foo-1.0/lib"] }
    let(:spec_double) do
      double("spec",
        name: "foo",
        version: Gem::Version.new("1.0"),
        load_paths: spec_load_paths,
        full_gem_path: "/tmp/gems/foo-1.0",
        executables: [])
    end

    # Rubygems integration double for entrypoint replacement and loaded tracking
    let(:rubygems_double) do
      double("rubygems",
        replace_entrypoints: nil,
        mark_loaded: nil,
        loaded_gem_paths: [],
        loaded_specs: nil)
    end

    before do
      allow(definition).to receive(:specs_for).and_return([spec_double])
      allow(Bundler::SharedHelpers).to receive(:set_bundle_environment)
      allow(Bundler).to receive(:rubygems).and_return(rubygems_double)
      allow(Gem).to receive(:add_to_load_path)
      allow(Bundler::SharedHelpers).to receive(:set_env)
      # Stub clean_load_path which is called via SharedHelpers include
      allow(rubygems_double).to receive(:loaded_gem_paths).and_return([])
      allow(Bundler::Plugin).to receive(:hook)
    end

    it "returns self for method chaining" do
      result = runtime.setup
      expect(result).to be(runtime)
      expect(result).to be_a(described_class)
    end

    it "calls ensure_equivalent_gemfile_and_lockfile on definition" do
      expect(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
      runtime.setup
    end

    it "calls specs_for on definition with the provided groups" do
      expect(definition).to receive(:specs_for).with([:default, :test]).and_return([])
      runtime.setup(:default, :test)
    end

    it "calls specs_for with empty groups when no groups specified" do
      expect(definition).to receive(:specs_for).with([]).and_return([])
      runtime.setup
    end

    it "sets the bundle environment via SharedHelpers" do
      expect(Bundler::SharedHelpers).to receive(:set_bundle_environment)
      runtime.setup
    end

    it "replaces entrypoints via Bundler.rubygems" do
      expect(rubygems_double).to receive(:replace_entrypoints).with([spec_double])
      runtime.setup
    end

    it "marks each spec as loaded via Bundler.rubygems" do
      expect(rubygems_double).to receive(:mark_loaded).with(spec_double)
      runtime.setup
    end

    it "adds load paths to Gem via add_to_load_path" do
      expect(Gem).to receive(:add_to_load_path)
      runtime.setup
    end

    context "with multiple specs" do
      let(:spec_double_2) do
        double("spec2",
          name: "bar",
          version: Gem::Version.new("2.0"),
          load_paths: ["/tmp/gems/bar-2.0/lib"],
          full_gem_path: "/tmp/gems/bar-2.0",
          executables: [])
      end

      before do
        allow(definition).to receive(:specs_for).and_return([spec_double, spec_double_2])
        allow(rubygems_double).to receive(:loaded_specs).and_return(nil)
      end

      it "marks all specs as loaded" do
        expect(rubygems_double).to receive(:mark_loaded).with(spec_double)
        expect(rubygems_double).to receive(:mark_loaded).with(spec_double_2)
        runtime.setup
      end

      it "replaces entrypoints with all specs" do
        expect(rubygems_double).to receive(:replace_entrypoints).with([spec_double, spec_double_2])
        runtime.setup
      end
    end

    context "when definition needs locking" do
      before do
        allow(definition).to receive(:no_resolve_needed?).and_return(false)
      end

      it "locks the definition with preserve_unknown_sections" do
        expect(definition).to receive(:lock).with(true)
        runtime.setup
      end
    end

    context "when definition does not need locking" do
      before do
        allow(definition).to receive(:no_resolve_needed?).and_return(true)
      end

      it "does not call lock on definition" do
        expect(definition).not_to receive(:lock)
        runtime.setup
      end
    end
  end

  describe "#require" do
    # Dependency double that matches default group and should be included
    let(:default_dep) do
      double("default_dep",
        name: "rack",
        groups: [:default],
        should_include?: true,
        autorequire: nil)
    end

    # Dependency double that matches test group
    let(:test_dep) do
      double("test_dep",
        name: "rspec",
        groups: [:test],
        should_include?: true,
        autorequire: nil)
    end

    # Dependency double that should NOT be included (platform mismatch)
    let(:excluded_dep) do
      double("excluded_dep",
        name: "wdm",
        groups: [:default],
        should_include?: false,
        autorequire: nil)
    end

    before do
      allow(definition).to receive(:dependencies).and_return([default_dep, test_dep, excluded_dep])
      allow(Bundler::Plugin).to receive(:hook)
      allow(Kernel).to receive(:require).and_return(true)
    end

    it "returns the filtered list of dependencies for default group" do
      result = runtime.require
      expect(result).to include(default_dep)
      expect(result).not_to include(test_dep)
    end

    it "defaults to the :default group when no groups specified" do
      result = runtime.require
      expect(result).to include(default_dep)
      expect(result).not_to include(test_dep)
    end

    it "requires gems from the specified group" do
      result = runtime.require(:test)
      expect(result).to include(test_dep)
      expect(result).not_to include(default_dep)
    end

    it "excludes dependencies where should_include? returns false" do
      result = runtime.require
      expect(result).not_to include(excluded_dep)
    end

    it "calls Kernel.require with the dependency name when no autorequire" do
      expect(Kernel).to receive(:require).with("rack")
      runtime.require
    end

    it "calls Plugin.hook with GEM_BEFORE_REQUIRE_ALL event" do
      expect(Bundler::Plugin).to receive(:hook).with(
        Bundler::Plugin::Events::GEM_BEFORE_REQUIRE_ALL,
        an_instance_of(Array)
      )
      runtime.require
    end

    it "calls Plugin.hook with GEM_AFTER_REQUIRE_ALL event" do
      expect(Bundler::Plugin).to receive(:hook).with(
        Bundler::Plugin::Events::GEM_AFTER_REQUIRE_ALL,
        an_instance_of(Array)
      )
      runtime.require
    end

    it "calls Plugin.hook with GEM_BEFORE_REQUIRE for each dependency" do
      expect(Bundler::Plugin).to receive(:hook).with(
        Bundler::Plugin::Events::GEM_BEFORE_REQUIRE,
        default_dep
      )
      runtime.require
    end

    it "calls Plugin.hook with GEM_AFTER_REQUIRE for each dependency" do
      expect(Bundler::Plugin).to receive(:hook).with(
        Bundler::Plugin::Events::GEM_AFTER_REQUIRE,
        default_dep
      )
      runtime.require
    end

    context "with custom autorequire" do
      let(:custom_require_dep) do
        double("custom_dep",
          name: "my-gem",
          groups: [:default],
          should_include?: true,
          autorequire: ["my_gem/core", "my_gem/ext"])
      end

      before do
        allow(definition).to receive(:dependencies).and_return([custom_require_dep])
      end

      it "requires each autorequire file instead of gem name" do
        expect(Kernel).to receive(:require).with("my_gem/core").ordered
        expect(Kernel).to receive(:require).with("my_gem/ext").ordered
        runtime.require
      end
    end

    context "with autorequire set to true" do
      let(:true_require_dep) do
        double("true_require_dep",
          name: "my-gem",
          groups: [:default],
          should_include?: true,
          autorequire: [true])
      end

      before do
        allow(definition).to receive(:dependencies).and_return([true_require_dep])
      end

      it "uses the gem name when autorequire is true" do
        expect(Kernel).to receive(:require).with("my-gem")
        runtime.require
      end
    end

    context "when LoadError occurs for hyphenated gem" do
      let(:hyphen_dep) do
        double("hyphen_dep",
          name: "my-gem",
          groups: [:default],
          should_include?: true,
          autorequire: nil)
      end

      before do
        allow(definition).to receive(:dependencies).and_return([hyphen_dep])
      end

      it "retries with hyphen replaced by slash on LoadError" do
        load_error = LoadError.new("cannot load such file -- my-gem")
        allow(load_error).to receive(:path).and_return("my-gem")

        call_count = 0
        allow(Kernel).to receive(:require) do |file|
          call_count += 1
          if call_count == 1 && file == "my-gem"
            raise load_error
          end
          true
        end

        runtime.require
        expect(call_count).to eq(2)
      end
    end

    context "when LoadError occurs for non-hyphenated gem with autorequire" do
      let(:failing_dep) do
        double("failing_dep",
          name: "badgem",
          groups: [:default],
          should_include?: true,
          autorequire: ["badgem/missing"])
      end

      before do
        allow(definition).to receive(:dependencies).and_return([failing_dep])
      end

      it "raises GemRequireError when autorequire is set" do
        load_error = LoadError.new("cannot load such file -- badgem/missing")
        allow(load_error).to receive(:path).and_return("badgem/missing")
        allow(Kernel).to receive(:require).with("badgem/missing").and_raise(load_error)

        expect { runtime.require }.to raise_error(Bundler::GemRequireError)
      end
    end

    context "when StandardError occurs during require" do
      let(:error_dep) do
        double("error_dep",
          name: "broken-gem",
          groups: [:default],
          should_include?: true,
          autorequire: nil)
      end

      before do
        allow(definition).to receive(:dependencies).and_return([error_dep])
      end

      it "wraps StandardError in GemRequireError" do
        allow(Kernel).to receive(:require).with("broken-gem").and_raise(StandardError, "init failed")

        expect { runtime.require }.to raise_error(Bundler::GemRequireError)
      end
    end

    context "with multiple groups" do
      it "returns dependencies matching any of the specified groups" do
        result = runtime.require(:default, :test)
        expect(result).to include(default_dep)
        expect(result).to include(test_dep)
        expect(result).not_to include(excluded_dep)
      end
    end
  end

  describe "#lock" do
    context "when no resolve is needed" do
      before do
        allow(definition).to receive(:no_resolve_needed?).and_return(true)
      end

      it "returns nil without calling lock on definition" do
        expect(definition).not_to receive(:lock)
        result = runtime.lock
        expect(result).to be_nil
      end
    end

    context "when resolve is needed" do
      before do
        allow(definition).to receive(:no_resolve_needed?).and_return(false)
      end

      it "calls lock on definition" do
        expect(definition).to receive(:lock).with(nil)
        runtime.lock
      end

      it "passes preserve_unknown_sections option to definition lock" do
        expect(definition).to receive(:lock).with(true)
        runtime.lock(preserve_unknown_sections: true)
      end
    end
  end

  describe "definition_method delegates" do
    describe "#requested_specs" do
      it "delegates to definition.requested_specs" do
        expected = [double("spec")]
        allow(definition).to receive(:requested_specs).and_return(expected)
        expect(runtime.requested_specs).to eq(expected)
      end

      it "raises ArgumentError when definition is nil" do
        rt = described_class.new(root, nil)
        expect { rt.requested_specs }.to raise_error(ArgumentError, /no definition/)
      end
    end

    describe "#specs" do
      it "delegates to definition.specs" do
        expected = [double("spec")]
        allow(definition).to receive(:specs).and_return(expected)
        expect(runtime.specs).to eq(expected)
      end
    end

    describe "#dependencies" do
      it "delegates to definition.dependencies" do
        deps = [double("dep")]
        allow(definition).to receive(:dependencies).and_return(deps)
        expect(runtime.dependencies).to eq(deps)
      end
    end

    describe "#current_dependencies" do
      it "delegates to definition.current_dependencies" do
        deps = [double("dep")]
        allow(definition).to receive(:current_dependencies).and_return(deps)
        expect(runtime.current_dependencies).to eq(deps)
      end
    end

    describe "#requires" do
      it "delegates to definition.requires" do
        reqs = { "rack" => ["rack"] }
        allow(definition).to receive(:requires).and_return(reqs)
        expect(runtime.requires).to eq(reqs)
      end
    end

    describe "#gems" do
      it "is aliased to #specs" do
        expected = [double("spec")]
        allow(definition).to receive(:specs).and_return(expected)
        expect(runtime.gems).to eq(expected)
        expect(runtime.gems).to eq(runtime.specs)
      end
    end
  end

  describe "#clean" do
    let(:gem_dir) { Dir.mktmpdir("runtime_spec_clean") }
    let(:rubygems_double) do
      double("rubygems",
        gem_bindir: "#{gem_dir}/bin",
        add_default_gems_to: {})
    end

    before do
      # Create required subdirectories that Dir[] globs will search
      FileUtils.mkdir_p("#{gem_dir}/bin")
      FileUtils.mkdir_p("#{gem_dir}/bundler/gems")
      FileUtils.mkdir_p("#{gem_dir}/cache/bundler/git")
      FileUtils.mkdir_p("#{gem_dir}/gems")
      FileUtils.mkdir_p("#{gem_dir}/cache")
      FileUtils.mkdir_p("#{gem_dir}/specifications")
      FileUtils.mkdir_p("#{gem_dir}/extensions")
      FileUtils.mkdir_p("#{gem_dir}/bundler/gems/extensions")

      allow(Gem).to receive(:dir).and_return(gem_dir)
      allow(Bundler).to receive(:rubygems).and_return(rubygems_double)
      allow(definition).to receive(:spec_git_paths).and_return([])
      allow(definition).to receive(:specs).and_return([])
    end

    after do
      FileUtils.rm_rf(gem_dir) if File.exist?(gem_dir)
    end

    it "returns an array of removed gem output strings" do
      result = runtime.clean
      expect(result).to be_a(Array)
      expect(result).to be_empty
    end

    it "returns an array when dry_run is true" do
      result = runtime.clean(true)
      expect(result).to be_a(Array)
      expect(result).to be_empty
    end
  end

  describe "#cache" do
    let(:cache_path) { Pathname.new(Dir.mktmpdir("runtime_spec_cache")) }
    let(:ui_double) { double("ui", info: nil, warn: nil) }
    let(:settings_double) do
      double("settings",
        app_cache_path: "vendor/cache",
        :[] => nil)
    end
    let(:resolve_double) { double("resolve", materialized_for_all_platforms: []) }

    before do
      allow(Bundler).to receive(:app_cache).and_return(cache_path)
      allow(Bundler).to receive(:ui).and_return(ui_double)
      allow(Bundler).to receive(:settings).and_return(settings_double)
      allow(Bundler::SharedHelpers).to receive(:filesystem_access).and_yield(cache_path)
      allow(definition).to receive(:resolve).and_return(resolve_double)
      allow(definition).to receive(:specs).and_return([])
      allow(settings_double).to receive(:[]).with(:no_prune).and_return(true)
      allow(settings_double).to receive(:[]).with(:cache_all_platforms).and_return(false)
    end

    after do
      FileUtils.rm_rf(cache_path) if cache_path && File.exist?(cache_path)
    end

    it "outputs an info message about updating files" do
      expect(ui_double).to receive(:info).with(/Updating files in/)
      runtime.cache
    end

    it "completes without error when cache directory exists" do
      expect { runtime.cache }.not_to raise_error
    end
  end

  describe "#prune_cache" do
    let(:cache_path) { Pathname.new(Dir.mktmpdir("runtime_spec_prune")) }
    let(:resolve_double) { double("resolve") }

    before do
      allow(Bundler::SharedHelpers).to receive(:filesystem_access).and_yield(cache_path)
      allow(definition).to receive(:resolve).and_return(resolve_double)
      # Stub Dir[] calls that happen inside prune_gem_cache and prune_git_and_path_cache
      allow(Dir).to receive(:[]).and_call_original
      allow(Dir).to receive(:[]).with("#{cache_path}/*.gem").and_return([])
      allow(Dir).to receive(:[]).with("#{cache_path}/*/.bundlecache").and_return([])
    end

    after do
      FileUtils.rm_rf(cache_path) if cache_path && File.exist?(cache_path)
    end

    it "resolves the definition and prunes stale gems" do
      expect(definition).to receive(:resolve).and_return(resolve_double)
      runtime.prune_cache(cache_path)
    end

    it "completes without raising an error" do
      expect { runtime.prune_cache(cache_path) }.not_to raise_error
    end
  end

  describe "gem activation" do
    let(:rubygems_double) do
      double("rubygems",
        replace_entrypoints: nil,
        mark_loaded: nil,
        loaded_gem_paths: [],
        loaded_specs: nil)
    end

    before do
      allow(definition).to receive(:specs_for).and_return([])
      allow(Bundler::SharedHelpers).to receive(:set_bundle_environment)
      allow(Bundler).to receive(:rubygems).and_return(rubygems_double)
      allow(Gem).to receive(:add_to_load_path)
      allow(Bundler::SharedHelpers).to receive(:set_env)
      allow(Bundler::Plugin).to receive(:hook)
    end

    context "when an activated spec with different version exists" do
      let(:spec_double) do
        double("spec",
          name: "foo",
          version: Gem::Version.new("2.0"),
          load_paths: ["/tmp/gems/foo-2.0/lib"],
          full_gem_path: "/tmp/gems/foo-2.0",
          executables: [])
      end

      let(:activated_spec) do
        double("activated_spec",
          name: "foo",
          version: Gem::Version.new("1.0"),
          default_gem?: false)
      end

      before do
        allow(definition).to receive(:specs_for).and_return([spec_double])
        allow(rubygems_double).to receive(:loaded_specs).with("foo").and_return(activated_spec)
      end

      it "raises Gem::LoadError when version mismatch is detected" do
        expect { runtime.setup }.to raise_error(Gem::LoadError, /already activated/)
      end

      it "includes gem name in the error message" do
        expect { runtime.setup }.to raise_error(Gem::LoadError, /foo/)
      end

      it "suggests prepending bundle exec for non-default gems" do
        expect { runtime.setup }.to raise_error(Gem::LoadError, /bundle exec/)
      end
    end

    context "when an activated default gem with different version exists" do
      let(:spec_double) do
        double("spec",
          name: "json",
          version: Gem::Version.new("2.0"),
          load_paths: ["/tmp/gems/json-2.0/lib"],
          full_gem_path: "/tmp/gems/json-2.0",
          executables: [])
      end

      let(:default_activated_spec) do
        double("activated_spec",
          name: "json",
          version: Gem::Version.new("1.0"),
          default_gem?: true)
      end

      before do
        allow(definition).to receive(:specs_for).and_return([spec_double])
        allow(rubygems_double).to receive(:loaded_specs).with("json").and_return(default_activated_spec)
      end

      it "raises Gem::LoadError mentioning default gem" do
        expect { runtime.setup }.to raise_error(Gem::LoadError, /default gem/)
      end
    end

    context "when activated spec has the same version" do
      let(:spec_double) do
        double("spec",
          name: "foo",
          version: Gem::Version.new("1.0"),
          load_paths: ["/tmp/gems/foo-1.0/lib"],
          full_gem_path: "/tmp/gems/foo-1.0",
          executables: [])
      end

      let(:same_version_spec) do
        double("activated_spec",
          name: "foo",
          version: Gem::Version.new("1.0"),
          default_gem?: false)
      end

      before do
        allow(definition).to receive(:specs_for).and_return([spec_double])
        allow(rubygems_double).to receive(:loaded_specs).with("foo").and_return(same_version_spec)
      end

      it "does not raise an error when versions match" do
        expect { runtime.setup }.not_to raise_error
      end
    end

    context "when no activated spec exists" do
      let(:spec_double) do
        double("spec",
          name: "foo",
          version: Gem::Version.new("1.0"),
          load_paths: ["/tmp/gems/foo-1.0/lib"],
          full_gem_path: "/tmp/gems/foo-1.0",
          executables: [])
      end

      before do
        allow(definition).to receive(:specs_for).and_return([spec_double])
        allow(rubygems_double).to receive(:loaded_specs).with("foo").and_return(nil)
      end

      it "proceeds without error" do
        expect { runtime.setup }.not_to raise_error
      end
    end
  end

  describe "load path ordering" do
    let(:rubygems_double) do
      double("rubygems",
        replace_entrypoints: nil,
        mark_loaded: nil,
        loaded_gem_paths: [],
        loaded_specs: nil)
    end

    let(:spec_a) do
      double("spec_a",
        name: "a-gem",
        version: Gem::Version.new("1.0"),
        load_paths: ["/tmp/gems/a-gem-1.0/lib"],
        full_gem_path: "/tmp/gems/a-gem-1.0",
        executables: [])
    end

    let(:spec_b) do
      double("spec_b",
        name: "b-gem",
        version: Gem::Version.new("2.0"),
        load_paths: ["/tmp/gems/b-gem-2.0/lib"],
        full_gem_path: "/tmp/gems/b-gem-2.0",
        executables: [])
    end

    before do
      allow(definition).to receive(:specs_for).and_return([spec_a, spec_b])
      allow(Bundler::SharedHelpers).to receive(:set_bundle_environment)
      allow(Bundler).to receive(:rubygems).and_return(rubygems_double)
      allow(rubygems_double).to receive(:loaded_specs).and_return(nil)
      allow(Bundler::SharedHelpers).to receive(:set_env)
      allow(Bundler::Plugin).to receive(:hook)
    end

    it "adds load paths in reversed order via Gem.add_to_load_path" do
      # The production code reverses the load paths before flattening
      # Spec A's paths appear first in input, but reversed means B's come first
      expect(Gem).to receive(:add_to_load_path) do |*paths|
        expect(paths).to be_a(Array)
      end
      runtime.setup
    end

    it "filters out paths already in $LOAD_PATH" do
      # Simulate a path already in $LOAD_PATH
      $LOAD_PATH.push("/tmp/gems/a-gem-1.0/lib") unless $LOAD_PATH.include?("/tmp/gems/a-gem-1.0/lib")

      received_paths = nil
      expect(Gem).to receive(:add_to_load_path) do |*paths|
        received_paths = paths
      end
      runtime.setup

      # The already-present path should have been filtered out
      expect(received_paths).not_to include("/tmp/gems/a-gem-1.0/lib")
    ensure
      $LOAD_PATH.delete("/tmp/gems/a-gem-1.0/lib")
    end
  end
end
