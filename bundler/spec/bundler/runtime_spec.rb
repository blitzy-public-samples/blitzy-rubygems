# frozen_string_literal: true

require "spec_helper"
require "bundler/runtime"

RSpec.describe Bundler::Runtime do
  # Shared test fixtures providing controlled root path and definition double
  let(:root) { Pathname.new("/tmp/test_app") }

  # Definition double responding to all methods invoked by Runtime's public API
  let(:definition) do
    double("definition",
      ensure_equivalent_gemfile_and_lockfile: nil,
      no_resolve_needed?: true,
      lock: nil,
      spec_git_paths: [])
  end

  # Standard runtime instance constructed from controlled fixtures
  let(:runtime) { described_class.new(root, definition) }

  describe "#initialize" do
    it "creates a Runtime instance that responds to setup and require" do
      rt = described_class.new(root, definition)
      expect(rt).to be_a(described_class)
      expect(rt).to respond_to(:setup)
      expect(rt).to respond_to(:require)
    end

    it "includes SharedHelpers in the class ancestry chain" do
      expect(described_class.ancestors).to include(Bundler::SharedHelpers)
      expect(runtime).to be_a(Bundler::SharedHelpers)
    end

    it "makes the definition accessible through delegated methods" do
      allow(definition).to receive(:requested_specs).and_return([])
      allow(definition).to receive(:specs).and_return([])
      expect(runtime.requested_specs).to eq([])
      expect(runtime.specs).to eq([])
    end

    it "exposes all definition_method delegates as public instance methods" do
      expect(runtime).to respond_to(:requested_specs)
      expect(runtime).to respond_to(:specs)
      expect(runtime).to respond_to(:dependencies)
      expect(runtime).to respond_to(:current_dependencies)
      expect(runtime).to respond_to(:requires)
    end

    it "exposes lock, cache, prune_cache, clean, and gems as public methods" do
      expect(runtime).to respond_to(:lock)
      expect(runtime).to respond_to(:cache)
      expect(runtime).to respond_to(:prune_cache)
      expect(runtime).to respond_to(:clean)
      expect(runtime).to respond_to(:gems)
    end
  end

  describe "#setup" do
    # Spec double simulating a loaded gem specification with load paths
    let(:spec_load_paths) { ["/tmp/gems/foo-1.0/lib"] }
    let(:spec_double) do
      double("spec",
        name: "foo",
        version: Gem::Version.new("1.0"),
        load_paths: spec_load_paths,
        full_gem_path: "/tmp/gems/foo-1.0",
        executables: [])
    end

    # RubyGems integration double for entrypoint replacement and loaded tracking
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
      allow(Bundler::Plugin).to receive(:hook)
    end

    it "returns self for method chaining after completing setup" do
      result = runtime.setup
      expect(result).to be(runtime)
      expect(result).to be_a(described_class)
    end

    it "ensures gemfile and lockfile equivalence then fetches specs" do
      expect(definition).to receive(:ensure_equivalent_gemfile_and_lockfile)
      expect(definition).to receive(:specs_for).with([]).and_return([spec_double])
      runtime.setup
    end

    it "passes provided groups through to specs_for on definition" do
      expect(definition).to receive(:specs_for).with([:default, :test]).and_return([])
      result = runtime.setup(:default, :test)
      expect(result).to be(runtime)
    end

    it "sets the bundle environment and replaces rubygems entrypoints" do
      expect(Bundler::SharedHelpers).to receive(:set_bundle_environment)
      expect(rubygems_double).to receive(:replace_entrypoints).with([spec_double])
      runtime.setup
    end

    it "marks each spec as loaded and returns self" do
      expect(rubygems_double).to receive(:mark_loaded).with(spec_double)
      result = runtime.setup
      expect(result).to be(runtime)
    end

    it "adds load paths via Gem.add_to_load_path and completes successfully" do
      expect(Gem).to receive(:add_to_load_path)
      result = runtime.setup
      expect(result).to be_a(described_class)
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

      it "marks all specs as loaded and replaces entrypoints with all specs" do
        expect(rubygems_double).to receive(:mark_loaded).with(spec_double)
        expect(rubygems_double).to receive(:mark_loaded).with(spec_double_2)
        expect(rubygems_double).to receive(:replace_entrypoints).with([spec_double, spec_double_2])
        runtime.setup
      end
    end

    context "when definition needs locking" do
      before do
        allow(definition).to receive(:no_resolve_needed?).and_return(false)
      end

      it "locks the definition with preserve_unknown_sections and returns self" do
        expect(definition).to receive(:lock).with(true)
        result = runtime.setup
        expect(result).to be(runtime)
      end
    end

    context "when definition does not need locking" do
      before do
        allow(definition).to receive(:no_resolve_needed?).and_return(true)
      end

      it "skips locking and still returns self" do
        expect(definition).not_to receive(:lock)
        result = runtime.setup
        expect(result).to be(runtime)
      end
    end
  end

  describe "#require" do
    # Dependency double matching the default group and platform-included
    let(:default_dep) do
      double("default_dep",
        name: "rack",
        groups: [:default],
        should_include?: true,
        autorequire: nil)
    end

    # Dependency double matching the test group only
    let(:test_dep) do
      double("test_dep",
        name: "rspec",
        groups: [:test],
        should_include?: true,
        autorequire: nil)
    end

    # Dependency double excluded by platform (should_include? returns false)
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

    it "defaults to the :default group and returns only matching dependencies" do
      result = runtime.require
      expect(result).to include(default_dep)
      expect(result).not_to include(test_dep)
    end

    it "filters to the specified group and excludes other groups" do
      result = runtime.require(:test)
      expect(result).to include(test_dep)
      expect(result).not_to include(default_dep)
    end

    it "excludes dependencies where should_include? returns false" do
      result = runtime.require
      expect(result).not_to include(excluded_dep)
      expect(result.length).to eq(1)
    end

    it "calls Kernel.require with the dependency name when autorequire is nil" do
      expect(Kernel).to receive(:require).with("rack")
      result = runtime.require
      expect(result).to include(default_dep)
    end

    it "hooks GEM_BEFORE_REQUIRE_ALL and GEM_AFTER_REQUIRE_ALL plugin events" do
      expect(Bundler::Plugin).to receive(:hook).with(
        Bundler::Plugin::Events::GEM_BEFORE_REQUIRE_ALL,
        an_instance_of(Array)
      )
      expect(Bundler::Plugin).to receive(:hook).with(
        Bundler::Plugin::Events::GEM_AFTER_REQUIRE_ALL,
        an_instance_of(Array)
      )
      runtime.require
    end

    it "hooks GEM_BEFORE_REQUIRE and GEM_AFTER_REQUIRE per dependency" do
      expect(Bundler::Plugin).to receive(:hook).with(
        Bundler::Plugin::Events::GEM_BEFORE_REQUIRE,
        default_dep
      )
      expect(Bundler::Plugin).to receive(:hook).with(
        Bundler::Plugin::Events::GEM_AFTER_REQUIRE,
        default_dep
      )
      runtime.require
    end

    context "with custom autorequire paths" do
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

      it "requires each autorequire file in order instead of the gem name" do
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

      it "uses the gem name when autorequire is the literal true value" do
        expect(Kernel).to receive(:require).with("my-gem")
        result = runtime.require
        expect(result).to include(true_require_dep)
      end
    end

    context "when LoadError occurs for a hyphenated gem with nil autorequire" do
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

      it "retries requiring with hyphen replaced by slash and returns the dep" do
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

        result = runtime.require
        expect(call_count).to eq(2)
        expect(result).to include(hyphen_dep)
      end
    end

    context "when LoadError occurs for a gem with explicit autorequire" do
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

      it "raises GemRequireError wrapping the LoadError with gem details" do
        load_error = LoadError.new("cannot load such file -- badgem/missing")
        allow(load_error).to receive(:path).and_return("badgem/missing")
        allow(Kernel).to receive(:require).with("badgem/missing").and_raise(load_error)

        error = nil
        begin
          runtime.require
        rescue Bundler::GemRequireError => e
          error = e
        end

        expect(error).not_to be_nil
        expect(error.message).to include("badgem")
      end
    end

    context "when StandardError occurs during gem require" do
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

      it "wraps the StandardError in GemRequireError with gem details" do
        allow(Kernel).to receive(:require).with("broken-gem").and_raise(StandardError, "init failed")

        error = nil
        begin
          runtime.require
        rescue Bundler::GemRequireError => e
          error = e
        end

        expect(error).not_to be_nil
        expect(error.message).to include("broken-gem")
      end
    end

    context "with multiple groups specified" do
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

      it "delegates to definition.lock with nil when no options given" do
        expect(definition).to receive(:lock).with(nil)
        expect { runtime.lock }.not_to raise_error
      end

      it "passes preserve_unknown_sections option through to definition.lock" do
        expect(definition).to receive(:lock).with(true)
        expect { runtime.lock(preserve_unknown_sections: true) }.not_to raise_error
      end
    end
  end

  describe "definition_method delegates" do
    describe "#requested_specs" do
      it "delegates to definition.requested_specs and returns the result" do
        expected = [double("spec")]
        allow(definition).to receive(:requested_specs).and_return(expected)
        expect(runtime.requested_specs).to eq(expected)
        expect(runtime.requested_specs).to be_a(Array)
      end

      it "raises ArgumentError when the definition is nil" do
        rt = described_class.new(root, nil)
        expect { rt.requested_specs }.to raise_error(ArgumentError, /no definition/)
        expect { rt.specs }.to raise_error(ArgumentError, /no definition/)
      end
    end

    describe "#specs" do
      it "delegates to definition.specs and returns the result" do
        expected = [double("spec")]
        allow(definition).to receive(:specs).and_return(expected)
        expect(runtime.specs).to eq(expected)
        expect(runtime.specs.length).to eq(1)
      end
    end

    describe "#dependencies" do
      it "delegates to definition.dependencies and returns the result" do
        deps = [double("dep")]
        allow(definition).to receive(:dependencies).and_return(deps)
        expect(runtime.dependencies).to eq(deps)
        expect(runtime.dependencies.length).to eq(1)
      end
    end

    describe "#current_dependencies" do
      it "delegates to definition.current_dependencies and returns the result" do
        deps = [double("dep")]
        allow(definition).to receive(:current_dependencies).and_return(deps)
        expect(runtime.current_dependencies).to eq(deps)
        expect(runtime.current_dependencies).to be_a(Array)
      end
    end

    describe "#requires" do
      it "delegates to definition.requires and returns the hash" do
        reqs = { "rack" => ["rack"] }
        allow(definition).to receive(:requires).and_return(reqs)
        expect(runtime.requires).to eq(reqs)
        expect(runtime.requires).to be_a(Hash)
      end
    end

    describe "#gems" do
      it "is aliased to #specs returning identical results" do
        expected = [double("spec")]
        allow(definition).to receive(:specs).and_return(expected)
        expect(runtime.gems).to eq(expected)
        expect(runtime.gems).to eq(runtime.specs)
      end
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

    context "when an activated non-default gem with different version exists" do
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

      it "raises Gem::LoadError reporting the gem name and activation conflict" do
        error = nil
        begin
          runtime.setup
        rescue Gem::LoadError => e
          error = e
        end

        expect(error).not_to be_nil
        expect(error.message).to include("foo")
        expect(error.message).to include("already activated")
      end

      it "suggests prepending bundle exec and sets error name attribute" do
        error = nil
        begin
          runtime.setup
        rescue Gem::LoadError => e
          error = e
        end

        expect(error.message).to include("bundle exec")
        expect(error.name).to eq("foo")
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

      it "raises Gem::LoadError mentioning it is a default gem with requirement" do
        error = nil
        begin
          runtime.setup
        rescue Gem::LoadError => e
          error = e
        end

        expect(error.message).to include("default gem")
        expect(error.requirement).to eq(Gem::Requirement.new("2.0"))
      end
    end

    context "when the activated spec has the same version" do
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

      it "does not raise an error and returns self" do
        expect { runtime.setup }.not_to raise_error
        expect(runtime.setup).to be(runtime)
      end
    end

    context "when no activated spec exists for the gem" do
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

      it "marks the spec as loaded and proceeds without error" do
        expect(rubygems_double).to receive(:mark_loaded).with(spec_double)
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

    it "collects load paths from all specs and passes them to Gem.add_to_load_path" do
      received_paths = nil
      expect(Gem).to receive(:add_to_load_path) do |*paths|
        received_paths = paths
      end
      runtime.setup
      expect(received_paths).to include("/tmp/gems/b-gem-2.0/lib")
      expect(received_paths).to include("/tmp/gems/a-gem-1.0/lib")
    end

    it "reverses the order of load paths before adding them" do
      received_paths = nil
      expect(Gem).to receive(:add_to_load_path) do |*paths|
        received_paths = paths
      end
      runtime.setup

      # Production code reverses: spec_b paths come before spec_a paths
      b_index = received_paths.index("/tmp/gems/b-gem-2.0/lib")
      a_index = received_paths.index("/tmp/gems/a-gem-1.0/lib")
      expect(b_index).not_to be_nil
      expect(b_index).to be < a_index
    end

    it "filters out paths already present in $LOAD_PATH" do
      $LOAD_PATH.push("/tmp/gems/a-gem-1.0/lib") unless $LOAD_PATH.include?("/tmp/gems/a-gem-1.0/lib")

      received_paths = nil
      expect(Gem).to receive(:add_to_load_path) do |*paths|
        received_paths = paths
      end
      runtime.setup

      expect(received_paths).not_to include("/tmp/gems/a-gem-1.0/lib")
      expect(received_paths).to include("/tmp/gems/b-gem-2.0/lib")
    ensure
      $LOAD_PATH.delete("/tmp/gems/a-gem-1.0/lib")
    end
  end
end
