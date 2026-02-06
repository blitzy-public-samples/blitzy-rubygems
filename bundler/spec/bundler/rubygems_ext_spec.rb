# frozen_string_literal: true

require "spec_helper"
require "bundler/rubygems_ext"
require "tmpdir"

RSpec.describe "Bundler RubyGems Extensions" do
  describe "Gem module compatibility shims" do
    describe ".freebsd_platform?" do
      it "is defined on Gem and returns a boolean value" do
        expect(Gem).to respond_to(:freebsd_platform?)
        result = Gem.freebsd_platform?
        expect([true, false]).to include(result)
      end

      it "returns consistent results across multiple calls" do
        first_result = Gem.freebsd_platform?
        second_result = Gem.freebsd_platform?
        expect(first_result).to eq(second_result)
        expect(first_result.class).to eq(second_result.class)
      end
    end

    describe ".open_file_with_flock" do
      it "is defined on Gem and yields an IO object for the given path" do
        expect(Gem).to respond_to(:open_file_with_flock)
        Dir.mktmpdir do |dir|
          path = File.join(dir, "flock_test_file")
          yielded_io = nil
          Gem.open_file_with_flock(path) {|io| yielded_io = io }
          expect(yielded_io).to be_a(IO)
        end
      end

      it "creates the file if it does not exist and allows write operations" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "new_flock_file")
          expect(File.exist?(path)).to be false
          Gem.open_file_with_flock(path) do |io|
            io.write("hello flock")
            io.rewind
            expect(io.read).to include("hello flock")
          end
          expect(File.exist?(path)).to be true
        end
      end

      it "opens an existing file without error and yields a usable IO" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "existing_flock_file")
          File.write(path, "preexisting")
          block_executed = false
          Gem.open_file_with_flock(path) do |io|
            block_executed = true
            expect(io).to be_a(IO)
          end
          expect(block_executed).to be true
        end
      end
    end

    describe ".open_file_with_lock" do
      it "is defined on Gem and yields to the provided block" do
        expect(Gem).to respond_to(:open_file_with_lock)
        Dir.mktmpdir do |dir|
          path = File.join(dir, "lock_target")
          File.write(path, "")
          block_executed = false
          Gem.open_file_with_lock(path) {|_io| block_executed = true }
          expect(block_executed).to be true
        end
      end

      it "creates a .lock file during execution and removes it afterward" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "lock_lifecycle")
          File.write(path, "")
          lock_path = "#{path}.lock"
          lock_existed_during = false
          Gem.open_file_with_lock(path) {|_io| lock_existed_during = File.exist?(lock_path) }
          expect(lock_existed_during).to be true
          expect(File.exist?(lock_path)).to be false
        end
      end

      it "cleans up the lock file even when the block raises an exception" do
        Dir.mktmpdir do |dir|
          path = File.join(dir, "lock_error_test")
          File.write(path, "")
          lock_path = "#{path}.lock"
          expect { Gem.open_file_with_lock(path) { raise "test error" } }.to raise_error(RuntimeError, "test error")
          expect(File.exist?(lock_path)).to be false
        end
      end
    end
  end

  describe "Gem::Platform extensions" do
    describe ".generic" do
      it "is defined on Gem::Platform and returns RUBY for nil input" do
        expect(Gem::Platform).to respond_to(:generic)
        expect(Gem::Platform.generic(nil)).to eq(Gem::Platform::RUBY)
      end

      it "returns RUBY for RUBY platform input" do
        result = Gem::Platform.generic(Gem::Platform::RUBY)
        expect(result).to eq(Gem::Platform::RUBY)
        expect(result).to be_truthy
      end

      it "returns the java generic for a java platform" do
        java_platform = Gem::Platform.new("java")
        result = Gem::Platform.generic(java_platform)
        expect(result).to eq(java_platform)
        expect(result).to be_a(Gem::Platform)
      end

      it "returns RUBY for standard linux and darwin platforms" do
        linux = Gem::Platform.new("x86_64-linux")
        darwin = Gem::Platform.new("arm64-darwin")
        expect(Gem::Platform.generic(linux)).to eq(Gem::Platform::RUBY)
        expect(Gem::Platform.generic(darwin)).to eq(Gem::Platform::RUBY)
      end

      it "returns a Gem::Platform for windows platforms" do
        mswin = Gem::Platform.new("x86-mswin32")
        result = Gem::Platform.generic(mswin)
        expect(result).to be_a(Gem::Platform)
        expect(result).not_to eq(Gem::Platform::RUBY)
      end

      it "returns RUBY for musl linux variant" do
        musl = Gem::Platform.new("x86_64-linux-musl")
        result = Gem::Platform.generic(musl)
        expect(result).to eq(Gem::Platform::RUBY)
        expect(result).to be_truthy
      end
    end

    describe ".platform_specificity_match" do
      it "is defined on Gem::Platform and returns -1 for exact match" do
        expect(Gem::Platform).to respond_to(:platform_specificity_match)
        platform = Gem::Platform.new("x86_64-linux")
        expect(Gem::Platform.platform_specificity_match(platform, platform)).to eq(-1)
      end

      it "returns 1_000_000 when spec_platform is nil or RUBY" do
        user = Gem::Platform.new("x86_64-linux")
        expect(Gem::Platform.platform_specificity_match(nil, user)).to eq(1_000_000)
        expect(Gem::Platform.platform_specificity_match(Gem::Platform::RUBY, user)).to eq(1_000_000)
      end

      it "returns 1_000_000 when user_platform is RUBY" do
        spec_p = Gem::Platform.new("x86_64-linux")
        result = Gem::Platform.platform_specificity_match(spec_p, Gem::Platform::RUBY)
        expect(result).to eq(1_000_000)
        expect(result).to be_a(Integer)
      end

      it "returns a non-negative numeric score for non-matching platforms" do
        spec_p = Gem::Platform.new("x86_64-linux")
        user_p = Gem::Platform.new("x86_64-linux-gnu")
        result = Gem::Platform.platform_specificity_match(spec_p, user_p)
        expect(result).to be_a(Integer)
        expect(result).to be >= 0
      end

      it "scores closer matches lower than or equal to distant matches" do
        user = Gem::Platform.new("x86_64-linux")
        close = Gem::Platform.new("universal-linux")
        far = Gem::Platform.new("arm64-darwin")
        close_score = Gem::Platform.platform_specificity_match(close, user)
        far_score = Gem::Platform.platform_specificity_match(far, user)
        expect(close_score).to be <= far_score
        expect(close_score).to be_a(Integer)
      end
    end

    describe ".sort_and_filter_best_platform_match" do
      it "is defined and returns a single-element array unchanged" do
        expect(Gem::Platform).to respond_to(:sort_and_filter_best_platform_match)
        single_spec = double("spec", platform: Gem::Platform.new("x86_64-linux"))
        result = Gem::Platform.sort_and_filter_best_platform_match([single_spec], Gem::Platform.new("x86_64-linux"))
        expect(result).to eq([single_spec])
      end

      it "filters to exact platform matches when available" do
        platform = Gem::Platform.new("x86_64-linux")
        exact_spec = double("exact_spec", platform: platform)
        generic_spec = double("generic_spec", platform: Gem::Platform::RUBY)
        result = Gem::Platform.sort_and_filter_best_platform_match([generic_spec, exact_spec], platform)
        expect(result).to include(exact_spec)
        expect(result).not_to include(generic_spec)
      end

      context "when no exact match exists" do
        it "returns sorted results as a non-empty array" do
          platform = Gem::Platform.new("x86_64-linux")
          spec_a = Gem::Specification.new {|s| s.name = "a"; s.version = "1.0"; s.platform = "ruby" }
          spec_b = Gem::Specification.new {|s| s.name = "a"; s.version = "1.0"; s.platform = "ruby" }
          result = Gem::Platform.sort_and_filter_best_platform_match([spec_a, spec_b], platform)
          expect(result).to be_an(Array)
          expect(result).not_to be_empty
        end
      end
    end

    describe ".sort_best_platform_match" do
      it "is defined and sorts specs with exact match first" do
        expect(Gem::Platform).to respond_to(:sort_best_platform_match)
        platform = Gem::Platform.new("x86_64-linux")
        exact = double("exact", platform: platform)
        ruby_spec = double("ruby_spec", platform: Gem::Platform::RUBY)
        result = Gem::Platform.sort_best_platform_match([ruby_spec, exact], platform)
        expect(result.first.platform).to eq(platform)
      end

      it "maintains stable sort order for specs with equal specificity" do
        platform = Gem::Platform.new("x86_64-linux")
        spec_a = double("spec_a", platform: Gem::Platform::RUBY)
        spec_b = double("spec_b", platform: Gem::Platform::RUBY)
        result = Gem::Platform.sort_best_platform_match([spec_a, spec_b], platform)
        expect(result).to eq([spec_a, spec_b])
        expect(result.first).to equal(spec_a)
      end
    end
  end

  describe "Gem::Specification extensions" do
    subject(:spec) do
      Gem::Specification.new do |s|
        s.name = "test_gem"
        s.version = "1.0.0"
        s.authors = ["Test Author"]
        s.summary = "A test gem"
      end
    end

    describe "#source and #source=" do
      it "allows setting and retrieving a custom source object" do
        mock_source = double("source")
        spec.source = mock_source
        expect(spec.source).to eq(mock_source)
        expect(spec.source).to be(mock_source)
      end

      it "responds to both source reader and writer methods" do
        expect(spec).to respond_to(:source)
        expect(spec).to respond_to(:source=)
      end
    end

    describe "#remote and #remote=" do
      it "allows setting and retrieving the remote attribute" do
        spec.remote = "https://rubygems.org"
        expect(spec.remote).to eq("https://rubygems.org")
        expect(spec).to respond_to(:remote=)
      end

      it "defaults to nil for a fresh specification" do
        fresh = Gem::Specification.new {|s| s.name = "fresh"; s.version = "1.0" }
        expect(fresh.remote).to be_nil
        expect(fresh).to respond_to(:remote)
      end
    end

    describe "#relative_loaded_from and #relative_loaded_from=" do
      it "allows setting and retrieving relative_loaded_from" do
        spec.relative_loaded_from = "test_gem.gemspec"
        expect(spec.relative_loaded_from).to eq("test_gem.gemspec")
        expect(spec).to respond_to(:relative_loaded_from=)
      end

      it "defaults to nil for a fresh specification" do
        fresh = Gem::Specification.new {|s| s.name = "fresh"; s.version = "1.0" }
        expect(fresh.relative_loaded_from).to be_nil
        expect(fresh).to respond_to(:relative_loaded_from)
      end
    end

    describe "#full_gem_path" do
      context "when source responds to root" do
        it "computes path via the source root directory" do
          spec.loaded_from = "gems/test_gem-1.0.0/test_gem.gemspec"
          source_obj = double("git_source")
          allow(source_obj).to receive(:root).and_return("/my/project")
          spec.source = source_obj
          result = spec.full_gem_path
          expect(result).to be_a(String)
          expect(result).to eq(File.expand_path("gems/test_gem-1.0.0", "/my/project"))
        end
      end

      context "when source does not respond to root" do
        it "returns a string for a standard specification" do
          expect(spec).to respond_to(:full_gem_path)
          result = spec.full_gem_path
          expect(result).to be_a(String)
        end
      end
    end

    describe "#loaded_from" do
      context "when relative_loaded_from is set with a path source" do
        it "resolves via source.path and relative_loaded_from" do
          path_obj = Pathname.new("/base/path")
          source_obj = double("path_source")
          allow(source_obj).to receive(:path).and_return(path_obj)
          spec.source = source_obj
          spec.relative_loaded_from = "test_gem.gemspec"
          result = spec.loaded_from
          expect(result).to eq("/base/path/test_gem.gemspec")
          expect(result).to be_a(String)
        end
      end

      context "when relative_loaded_from is not set" do
        it "falls back to original loaded_from behavior" do
          expect(spec).to respond_to(:loaded_from)
          result = spec.loaded_from
          expect(result).to be_nil.or be_a(String)
        end
      end
    end

    describe "#load_paths" do
      it "delegates to full_require_paths and returns an Array" do
        result = spec.load_paths
        expect(result).to eq(spec.full_require_paths)
        expect(result).to be_an(Array)
      end
    end

    describe "#extension_dir" do
      it "responds to the method and returns a string path" do
        expect(spec).to respond_to(:extension_dir)
        result = spec.extension_dir
        expect(result).to be_a(String)
      end
    end

    describe "#gem_dir" do
      it "returns the same value as full_gem_path" do
        result = spec.gem_dir
        expect(result).to eq(spec.full_gem_path)
        expect(result).to be_a(String)
      end
    end

    describe "#insecurely_materialized?" do
      it "returns false for any specification" do
        expect(spec.insecurely_materialized?).to be_falsey
        other = Gem::Specification.new {|s| s.name = "other"; s.version = "2.0" }
        expect(other.insecurely_materialized?).to be false
      end
    end

    describe "#groups" do
      it "returns an empty array by default that is memoized" do
        result = spec.groups
        expect(result).to eq([])
        expect(spec.groups).to be(result)
      end

      it "returns an Array instance with zero length" do
        expect(spec.groups).to be_an(Array)
        expect(spec.groups.length).to eq(0)
      end
    end

    describe "#git_version" do
      it "returns nil when source is not a Git source" do
        expect(spec).to respond_to(:git_version)
        expect(spec.git_version).to be_nil
      end

      it "returns nil when loaded_from is nil" do
        fresh = Gem::Specification.new {|s| s.name = "x"; s.version = "1.0" }
        expect(fresh.loaded_from).to be_nil
        expect(fresh.git_version).to be_nil
      end
    end

    describe "#to_gemfile" do
      it "returns a string starting with the rubygems source declaration" do
        result = spec.to_gemfile
        expect(result).to be_a(String)
        expect(result).to include("source 'https://rubygems.org'")
      end

      it "includes runtime dependencies as gem declarations" do
        spec.add_dependency("rack", "~> 2.0")
        result = spec.to_gemfile
        expect(result).to include('gem "rack"')
        expect(result).to include("~> 2.0")
      end

      it "wraps development dependencies in a group block" do
        spec.add_development_dependency("rspec", "~> 3.0")
        result = spec.to_gemfile
        expect(result).to include("group :development")
        expect(result).to include('gem "rspec"')
      end

      context "when spec has no dependencies" do
        it "does not include group block but starts with source" do
          result = spec.to_gemfile
          expect(result).to start_with("source")
          expect(result).not_to include("group :development")
        end
      end
    end

    describe "#nondevelopment_dependencies" do
      before do
        spec.add_dependency("rack", "~> 2.0")
        spec.add_development_dependency("rspec", "~> 3.0")
      end

      it "returns only runtime dependencies excluding development ones" do
        result = spec.nondevelopment_dependencies
        names = result.map(&:name)
        expect(names).to include("rack")
        expect(names).not_to include("rspec")
      end

      it "returns an empty array when there are no runtime dependencies" do
        empty_spec = Gem::Specification.new {|s| s.name = "empty"; s.version = "1.0" }
        result = empty_spec.nondevelopment_dependencies
        expect(result).to eq([])
        expect(result).to be_an(Array)
      end
    end

    describe "#installation_missing?" do
      it "responds to the method and returns a boolean for a non-existent gem dir" do
        expect(spec).to respond_to(:installation_missing?)
        expect([true, false]).to include(spec.installation_missing?)
      end
    end

    describe "#lock_name" do
      it "returns a formatted name with version in parentheses" do
        result = spec.lock_name
        expect(result).to eq("test_gem (1.0.0)")
        expect(result).to be_a(String)
      end

      it "memoizes the result and delegates to name_tuple.lock_name" do
        first_call = spec.lock_name
        expect(spec.lock_name).to equal(first_call)
        expect(spec.lock_name).to eq(spec.name_tuple.lock_name)
      end
    end

    describe "#validate_for_resolution" do
      it "responds to the method and does not raise for a valid spec" do
        valid = Gem::Specification.new do |s|
          s.name = "valid_gem"
          s.version = "1.0.0"
          s.authors = ["Author"]
          s.summary = "Summary"
        end
        expect(valid).to respond_to(:validate_for_resolution)
        expect { valid.validate_for_resolution }.not_to raise_error
      end
    end

    describe "MatchMetadata inclusion" do
      it "provides metadata matching methods on Gem::Specification" do
        expect(spec).to respond_to(:matches_current_metadata?)
        expect(spec).to respond_to(:matches_current_ruby?)
        expect(spec).to respond_to(:matches_current_rubygems?)
      end

      it "matches current ruby and rubygems for a spec with no constraints" do
        expect(spec.matches_current_ruby?).to be true
        expect(spec.matches_current_rubygems?).to be true
      end
    end
  end

  describe "Gem::Dependency extensions" do
    subject(:dep) { Gem::Dependency.new("test_dep", "~> 1.0") }

    describe "#source and #source=" do
      it "allows setting and retrieving a source object" do
        mock_source = double("source")
        dep.source = mock_source
        expect(dep.source).to eq(mock_source)
        expect(dep).to respond_to(:source=)
      end

      it "defaults to nil for a fresh dependency" do
        fresh = Gem::Dependency.new("fresh", ">= 0")
        expect(fresh.source).to be_nil
        expect(fresh).to respond_to(:source)
      end
    end

    describe "#groups and #groups=" do
      it "allows setting and retrieving groups" do
        dep.groups = [:development, :test]
        expect(dep.groups).to eq([:development, :test])
        expect(dep.groups).to be_an(Array)
      end

      it "defaults to nil for a fresh dependency" do
        fresh = Gem::Dependency.new("fresh", ">= 0")
        expect(fresh.groups).to be_nil
        expect(fresh).to respond_to(:groups=)
      end
    end

    describe "#to_lock" do
      it "formats the dependency with name indented by two spaces and version in parens" do
        result = dep.to_lock
        expect(result).to start_with("  test_dep")
        expect(result).to match(/test_dep \(.*~>.*1\.0.*\)/)
      end

      it "omits parentheses when the requirement is none (no version constraint)" do
        no_req = Gem::Dependency.new("any_gem")
        result = no_req.to_lock
        expect(result).to eq("  any_gem")
        expect(result).to start_with("  ")
      end

      context "with multiple version requirements" do
        it "includes the gem name and parenthesized constraints" do
          req = Gem::Requirement.new([">= 1.0", "< 3.0"])
          multi = Gem::Dependency.new("multi_req", req)
          result = multi.to_lock
          expect(result).to include("multi_req")
          expect(result).to include("(")
        end
      end
    end

    describe "#encode_with" do
      it "encodes name and requirement to the coder hash" do
        coder = {}
        dep.encode_with(coder)
        expect(coder).to have_key("name")
        expect(coder["name"]).to eq("test_dep")
      end

      it "includes all expected keys: name, requirement, type, prerelease, version_requirements" do
        coder = {}
        dep.encode_with(coder)
        %w[name requirement type prerelease version_requirements].each do |key|
          expect(coder).to have_key(key)
        end
        expect(coder.keys.length).to be >= 5
      end
    end

    describe "#eql?" do
      it "is consistent with == for equivalent dependencies" do
        dep_a = Gem::Dependency.new("test", "~> 1.0")
        dep_b = Gem::Dependency.new("test", "~> 1.0")
        expect(dep_a.eql?(dep_b)).to eq(dep_a == dep_b)
        expect(dep_a.eql?(dep_b)).to be true
      end

      it "returns false for non-equivalent dependencies" do
        dep_a = Gem::Dependency.new("gem_a", "~> 1.0")
        dep_b = Gem::Dependency.new("gem_b", "~> 2.0")
        expect(dep_a.eql?(dep_b)).to eq(dep_a == dep_b)
        expect(dep_a.eql?(dep_b)).to be_falsey
      end
    end

    describe "#force_ruby_platform" do
      it "is available via ForcePlatform inclusion and responds to the accessor" do
        expect(Gem::Dependency.ancestors).to include(Bundler::ForcePlatform)
        expect(dep).to respond_to(:force_ruby_platform)
      end
    end
  end

  describe "Gem::BasicSpecification extensions" do
    let(:basic_spec) do
      Gem::Specification.new {|s| s.name = "basic"; s.version = "1.0" }
    end

    describe "#ignored?" do
      it "is available and returns false for a spec with no missing extensions" do
        expect(basic_spec).to respond_to(:ignored?)
        expect(basic_spec.ignored?).to eq(false)
      end
    end

    describe "#installable_on_platform?" do
      it "is available on Gem::Specification via BasicSpecification" do
        expect(basic_spec).to respond_to(:installable_on_platform?)
        expect(Gem::BasicSpecification.method_defined?(:installable_on_platform?)).to be true
      end
    end
  end

  describe "Gem::NameTuple extensions" do
    describe "#lock_name" do
      it "returns formatted name with version for RUBY platform" do
        tuple = Gem::NameTuple.new("mygem", Gem::Version.new("2.3.4"), Gem::Platform::RUBY)
        result = tuple.lock_name
        expect(result).to eq("mygem (2.3.4)")
        expect(result).to be_a(String)
      end

      it "includes platform in the lock name for non-RUBY string platform" do
        tuple = Gem::NameTuple.new("mygem", Gem::Version.new("2.3.4"), "java")
        result = tuple.lock_name
        expect(result).to eq("mygem (2.3.4-java)")
        expect(result).to include("java")
      end

      it "handles platform as a Gem::Platform object" do
        platform = Gem::Platform.new("x86_64-linux")
        tuple = Gem::NameTuple.new("mygem", Gem::Version.new("1.0.0"), platform)
        result = tuple.lock_name
        expect(result).to eq("mygem (1.0.0-x86_64-linux)")
        expect(result).to include("x86_64-linux")
      end
    end

    describe "platform coercion in initialize" do
      it "stores Gem::Platform objects as strings" do
        platform = Gem::Platform.new("x86_64-linux")
        tuple = Gem::NameTuple.new("test", Gem::Version.new("1.0"), platform)
        expect(tuple.platform).to be_a(String)
        expect(tuple.platform).to eq("x86_64-linux")
      end

      it "handles string platform directly and defaults to ruby" do
        string_tuple = Gem::NameTuple.new("test", Gem::Version.new("1.0"), "ruby")
        expect(string_tuple.platform).to eq("ruby")
        default_tuple = Gem::NameTuple.new("test", Gem::Version.new("1.0"))
        expect(default_tuple.platform).to eq("ruby")
      end
    end
  end

  describe "Gem::StubSpecification extensions" do
    it "has BetterPermissionError prepended and is a module" do
      expect(Gem::StubSpecification.ancestors).to include(Gem::BetterPermissionError)
      expect(Gem::BetterPermissionError).to be_a(Module)
    end
  end

  describe "VALIDATES_FOR_RESOLUTION constant" do
    it "is defined on Gem and holds a boolean value" do
      expect(defined?(Gem::VALIDATES_FOR_RESOLUTION)).to be_truthy
      expect([true, false]).to include(Gem::VALIDATES_FOR_RESOLUTION)
    end
  end

  describe "integration behaviors" do
    describe "Gem::Specification with mixed dependencies" do
      subject(:complex_spec) do
        Gem::Specification.new do |s|
          s.name = "complex_gem"
          s.version = "2.0.0"
          s.authors = ["Test"]
          s.summary = "Complex gem"
          s.add_dependency("rack", "~> 2.0")
          s.add_dependency("json", ">= 1.8")
          s.add_development_dependency("rspec", "~> 3.0")
          s.add_development_dependency("rubocop", "~> 1.0")
        end
      end

      it "correctly separates development and non-development dependencies" do
        nondev = complex_spec.nondevelopment_dependencies
        dev = complex_spec.development_dependencies
        all_deps = complex_spec.dependencies
        expect(nondev.map(&:name)).to match_array(["rack", "json"])
        expect(dev.map(&:name)).to match_array(["rspec", "rubocop"])
        expect(nondev.length + dev.length).to eq(all_deps.length)
      end

      it "generates a complete gemfile with all dependency groups" do
        gemfile = complex_spec.to_gemfile
        expect(gemfile).to include("source 'https://rubygems.org'")
        expect(gemfile).to include('gem "rack"')
        expect(gemfile).to include("group :development")
        expect(gemfile).to include('gem "rspec"')
      end
    end

    describe "lock name consistency between Gem::Specification and Gem::NameTuple" do
      it "produces matching lock names for ruby platform gems" do
        gem_spec = Gem::Specification.new {|s| s.name = "consistent_gem"; s.version = "3.2.1" }
        tuple = Gem::NameTuple.new("consistent_gem", Gem::Version.new("3.2.1"), Gem::Platform::RUBY)
        expect(gem_spec.lock_name).to eq(tuple.lock_name)
        expect(gem_spec.lock_name).to eq("consistent_gem (3.2.1)")
      end
    end

    describe "Gem::Dependency lock formatting variants" do
      it "formats versioned and unversioned dependencies differently" do
        versioned = Gem::Dependency.new("rails", "~> 7.0")
        unversioned = Gem::Dependency.new("bundler")
        expect(versioned.to_lock).to include("(")
        expect(unversioned.to_lock).to eq("  bundler")
      end

      it "formats multiple requirement dependencies with parentheses" do
        multi = Gem::Dependency.new("nokogiri", [">= 1.10", "< 2.0"])
        result = multi.to_lock
        expect(result).to start_with("  nokogiri")
        expect(result).to include("(")
      end
    end

    describe "Gem::Platform generic resolution for common platforms" do
      it "resolves standard platforms to RUBY but preserves java" do
        linux = Gem::Platform.new("x86_64-linux")
        java = Gem::Platform.new("java")
        expect(Gem::Platform.generic(linux)).to eq(Gem::Platform::RUBY)
        expect(Gem::Platform.generic(java)).to eq(java)
      end

      it "resolves darwin platform to RUBY" do
        darwin = Gem::Platform.new("arm64-darwin")
        result = Gem::Platform.generic(darwin)
        expect(result).to eq(Gem::Platform::RUBY)
        expect(result).to be_truthy
      end
    end
  end
end
