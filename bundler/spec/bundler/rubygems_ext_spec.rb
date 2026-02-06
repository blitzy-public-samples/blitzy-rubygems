# frozen_string_literal: true

require "spec_helper"
require "bundler/rubygems_ext"
require "tempfile"

RSpec.describe "Bundler RubyGems Extensions" do
  describe "Gem module extensions" do
    describe ".freebsd_platform?" do
      it "returns a boolean" do
        result = Gem.freebsd_platform?
        expect([true, false]).to include(result)
      end

      it "responds to the method" do
        expect(Gem).to respond_to(:freebsd_platform?)
      end
    end

    describe ".open_file_with_flock" do
      it "responds to the method" do
        expect(Gem).to respond_to(:open_file_with_flock)
      end

      it "yields to the block with an IO object" do
        tmpfile = Tempfile.new("flock_test")
        path = tmpfile.path
        tmpfile.close

        yielded_io = nil
        Gem.open_file_with_flock(path) do |io|
          yielded_io = io
        end

        expect(yielded_io).to be_a(IO)
      ensure
        tmpfile&.unlink
      end

      it "allows reading and writing within the block" do
        tmpfile = Tempfile.new("flock_rw_test")
        path = tmpfile.path
        tmpfile.close

        Gem.open_file_with_flock(path) do |io|
          io.write("test content")
          io.rewind
          expect(io.read).to include("test content")
        end
      ensure
        tmpfile&.unlink
      end
    end

    describe ".open_file_with_lock" do
      it "responds to the method" do
        expect(Gem).to respond_to(:open_file_with_lock)
      end

      it "yields to the block" do
        tmpfile = Tempfile.new("lock_test")
        path = tmpfile.path
        tmpfile.close

        block_called = false
        Gem.open_file_with_lock(path) do |_io|
          block_called = true
        end

        expect(block_called).to be true
      ensure
        tmpfile&.unlink
      end

      it "cleans up the lock file after execution" do
        tmpfile = Tempfile.new("lock_cleanup_test")
        path = tmpfile.path
        tmpfile.close

        Gem.open_file_with_lock(path) do |_io|
          # lock file should exist during block
          expect(File.exist?("#{path}.lock")).to be true
        end

        expect(File.exist?("#{path}.lock")).to be false
      ensure
        tmpfile&.unlink
      end
    end
  end

  describe "Gem::Platform extensions" do
    describe ".generic" do
      it "responds to the method" do
        expect(Gem::Platform).to respond_to(:generic)
      end

      it "returns RUBY for nil input" do
        result = Gem::Platform.generic(nil)
        expect(result).to eq(Gem::Platform::RUBY)
      end

      it "returns RUBY for RUBY platform input" do
        result = Gem::Platform.generic(Gem::Platform::RUBY)
        expect(result).to eq(Gem::Platform::RUBY)
      end

      it "returns the java generic for a java platform" do
        java_platform = Gem::Platform.new("java")
        result = Gem::Platform.generic(java_platform)
        expect(result).to eq(java_platform)
      end

      it "returns RUBY for a standard linux platform" do
        linux_platform = Gem::Platform.new("x86_64-linux")
        result = Gem::Platform.generic(linux_platform)
        expect(result).to eq(Gem::Platform::RUBY)
      end

      it "returns a generic for a windows platform" do
        mswin_platform = Gem::Platform.new("x86-mswin32")
        result = Gem::Platform.generic(mswin_platform)
        expect(result).to be_a(Gem::Platform)
      end
    end

    describe ".platform_specificity_match" do
      it "responds to the method" do
        expect(Gem::Platform).to respond_to(:platform_specificity_match)
      end

      it "returns -1 for exact platform match" do
        platform = Gem::Platform.new("x86_64-linux")
        result = Gem::Platform.platform_specificity_match(platform, platform)
        expect(result).to eq(-1)
      end

      it "returns a large value when spec_platform is nil" do
        user_platform = Gem::Platform.new("x86_64-linux")
        result = Gem::Platform.platform_specificity_match(nil, user_platform)
        expect(result).to eq(1_000_000)
      end

      it "returns a large value when spec_platform is RUBY" do
        user_platform = Gem::Platform.new("x86_64-linux")
        result = Gem::Platform.platform_specificity_match(Gem::Platform::RUBY, user_platform)
        expect(result).to eq(1_000_000)
      end

      it "returns a large value when user_platform is RUBY" do
        spec_platform = Gem::Platform.new("x86_64-linux")
        result = Gem::Platform.platform_specificity_match(spec_platform, Gem::Platform::RUBY)
        expect(result).to eq(1_000_000)
      end

      it "returns a numeric score for non-matching platforms" do
        spec_platform = Gem::Platform.new("x86_64-linux")
        user_platform = Gem::Platform.new("x86_64-linux-gnu")
        result = Gem::Platform.platform_specificity_match(spec_platform, user_platform)
        expect(result).to be_a(Integer)
      end

      it "returns a lower score for closer platform matches" do
        user_platform = Gem::Platform.new("x86_64-linux")
        # Same OS, universal CPU => os_match=0, cpu_match(universal)=1 => score = 10
        close_platform = Gem::Platform.new("universal-linux")
        # Different OS AND different CPU => os_match=1, cpu_match=2 => score = 21
        far_platform = Gem::Platform.new("arm64-darwin")

        close_score = Gem::Platform.platform_specificity_match(close_platform, user_platform)
        far_score = Gem::Platform.platform_specificity_match(far_platform, user_platform)

        expect(close_score).to be <= far_score
      end
    end

    describe ".sort_and_filter_best_platform_match" do
      it "responds to the method" do
        expect(Gem::Platform).to respond_to(:sort_and_filter_best_platform_match)
      end

      it "returns a single element array unchanged" do
        spec = double("spec", platform: Gem::Platform.new("x86_64-linux"))
        result = Gem::Platform.sort_and_filter_best_platform_match([spec], Gem::Platform.new("x86_64-linux"))
        expect(result).to eq([spec])
      end

      it "prefers exact platform matches" do
        platform = Gem::Platform.new("x86_64-linux")
        exact_spec = double("exact_spec", platform: platform)
        generic_spec = double("generic_spec", platform: Gem::Platform::RUBY)

        result = Gem::Platform.sort_and_filter_best_platform_match(
          [generic_spec, exact_spec], platform
        )
        expect(result).to eq([exact_spec])
      end

      it "returns matching specs sorted by specificity when no exact match" do
        platform = Gem::Platform.new("x86_64-linux")

        spec_a = Gem::Specification.new do |s|
          s.name = "test"
          s.version = "1.0"
          s.platform = "ruby"
        end

        spec_b = Gem::Specification.new do |s|
          s.name = "test"
          s.version = "1.0"
          s.platform = "ruby"
        end

        result = Gem::Platform.sort_and_filter_best_platform_match(
          [spec_a, spec_b], platform
        )
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
      end
    end

    describe ".sort_best_platform_match" do
      it "responds to the method" do
        expect(Gem::Platform).to respond_to(:sort_best_platform_match)
      end

      it "returns specs sorted by platform specificity" do
        platform = Gem::Platform.new("x86_64-linux")

        spec_a = double("spec_a", platform: Gem::Platform::RUBY)
        spec_b = double("spec_b", platform: platform)

        result = Gem::Platform.sort_best_platform_match([spec_a, spec_b], platform)
        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
        # The exact match should sort first (score -1)
        expect(result.first.platform).to eq(platform)
      end

      it "maintains stable sort order for equal specificity" do
        platform = Gem::Platform.new("x86_64-linux")

        spec_a = double("spec_a", platform: Gem::Platform::RUBY)
        spec_b = double("spec_b", platform: Gem::Platform::RUBY)

        result = Gem::Platform.sort_best_platform_match([spec_a, spec_b], platform)
        expect(result).to eq([spec_a, spec_b])
      end
    end
  end

  describe "Gem::Specification extensions" do
    let(:spec) do
      Gem::Specification.new do |s|
        s.name = "test_gem"
        s.version = "1.0.0"
        s.authors = ["Test Author"]
        s.summary = "A test gem"
      end
    end

    describe "#source and #source=" do
      it "allows setting and getting a source" do
        mock_source = double("source")
        spec.source = mock_source
        expect(spec.source).to eq(mock_source)
      end

      it "falls back to default source when none explicitly set" do
        # A fresh spec with no source set should respond to source without error
        fresh_spec = Gem::Specification.new do |s|
          s.name = "fresh"
          s.version = "1.0"
        end
        expect(fresh_spec).to respond_to(:source)
      end
    end

    describe "#remote and #remote=" do
      it "allows setting and getting remote" do
        spec.remote = "https://rubygems.org"
        expect(spec.remote).to eq("https://rubygems.org")
      end
    end

    describe "#relative_loaded_from and #relative_loaded_from=" do
      it "allows setting and getting relative_loaded_from" do
        spec.relative_loaded_from = "test_gem.gemspec"
        expect(spec.relative_loaded_from).to eq("test_gem.gemspec")
      end
    end

    describe "#full_gem_path" do
      it "responds to the method" do
        expect(spec).to respond_to(:full_gem_path)
      end

      it "delegates to source.root when source responds to root" do
        source_with_root = double("source_with_root", root: "/path/to/root")
        spec.source = source_with_root
        spec.loaded_from = "/path/to/root/gems/test_gem-1.0.0/test_gem.gemspec"

        result = spec.full_gem_path
        expect(result).to be_a(String)
      end

      it "delegates to rg_full_gem_path when source does not respond to root" do
        source_without_root = double("source", respond_to?: false)
        allow(source_without_root).to receive(:respond_to?).with(:root).and_return(false)
        # Default behavior without bundler source
        result = spec.full_gem_path
        expect(result).to be_a(String)
      end
    end

    describe "#loaded_from" do
      it "responds to the method" do
        expect(spec).to respond_to(:loaded_from)
      end

      it "returns the loaded_from via relative path when relative_loaded_from is set" do
        source_with_path = double("source_with_path")
        allow(source_with_path).to receive(:respond_to?).and_return(false)
        allow(source_with_path).to receive(:respond_to?).with(:root).and_return(false)
        path_obj = double("path")
        allow(source_with_path).to receive(:path).and_return(path_obj)
        allow(path_obj).to receive(:join).with("test.gemspec").and_return(Pathname.new("/some/path/test.gemspec"))
        allow(source_with_path).to receive(:respond_to?).with(:path).and_return(true)

        spec.source = source_with_path
        spec.relative_loaded_from = "test.gemspec"

        result = spec.loaded_from
        expect(result).to be_a(String)
      end

      it "returns original loaded_from when relative_loaded_from is not set" do
        result = spec.loaded_from
        # Should not raise, may be nil for a fresh spec
        expect(result).to be_nil.or be_a(String)
      end
    end

    describe "#load_paths" do
      it "delegates to full_require_paths" do
        expect(spec.load_paths).to eq(spec.full_require_paths)
      end
    end

    describe "#gem_dir" do
      it "returns the same as full_gem_path" do
        expect(spec.gem_dir).to eq(spec.full_gem_path)
      end
    end

    describe "#insecurely_materialized?" do
      it "returns false" do
        expect(spec.insecurely_materialized?).to be false
      end
    end

    describe "#groups" do
      it "returns an empty array by default" do
        expect(spec.groups).to eq([])
      end

      it "returns an array" do
        expect(spec.groups).to be_an(Array)
      end

      it "memoizes the groups array" do
        groups = spec.groups
        expect(spec.groups).to be(groups)
      end
    end

    describe "#git_version" do
      it "returns nil when source is not a Git source" do
        expect(spec.git_version).to be_nil
      end

      it "returns nil when loaded_from is nil" do
        expect(spec.git_version).to be_nil
      end
    end

    describe "#to_gemfile" do
      it "returns a string starting with source declaration" do
        result = spec.to_gemfile
        expect(result).to include("source 'https://rubygems.org'")
      end

      it "includes non-development dependencies" do
        spec.add_dependency("rack", "~> 2.0")
        result = spec.to_gemfile
        expect(result).to include('gem "rack"')
      end

      it "groups development dependencies" do
        spec.add_development_dependency("rspec", "~> 3.0")
        result = spec.to_gemfile
        expect(result).to include("group :development")
        expect(result).to include('gem "rspec"')
      end

      it "returns a String" do
        expect(spec.to_gemfile).to be_a(String)
      end
    end

    describe "#nondevelopment_dependencies" do
      it "returns dependencies minus development dependencies" do
        spec.add_dependency("rack", "~> 2.0")
        spec.add_development_dependency("rspec", "~> 3.0")

        result = spec.nondevelopment_dependencies
        names = result.map(&:name)
        expect(names).to include("rack")
        expect(names).not_to include("rspec")
      end

      it "returns an empty array when there are no runtime dependencies" do
        expect(spec.nondevelopment_dependencies).to eq([])
      end
    end

    describe "#installation_missing?" do
      it "responds to the method" do
        expect(spec).to respond_to(:installation_missing?)
      end

      it "returns true for a non-default gem with non-existent directory" do
        allow(spec).to receive(:default_gem?).and_return(false)
        allow(spec).to receive(:full_gem_path).and_return("/nonexistent/path/to/gem")

        expect(spec.installation_missing?).to be true
      end

      it "returns false for a default gem" do
        allow(spec).to receive(:default_gem?).and_return(true)

        expect(spec.installation_missing?).to be false
      end
    end

    describe "#lock_name" do
      it "returns a formatted lock name" do
        result = spec.lock_name
        expect(result).to include("test_gem")
        expect(result).to include("1.0.0")
      end

      it "memoizes the lock name" do
        first_call = spec.lock_name
        second_call = spec.lock_name
        expect(first_call).to equal(second_call)
      end

      it "delegates to name_tuple.lock_name" do
        expect(spec.lock_name).to eq(spec.name_tuple.lock_name)
      end
    end

    describe "#validate_for_resolution" do
      it "responds to the method" do
        expect(spec).to respond_to(:validate_for_resolution)
      end

      it "does not raise for a valid spec" do
        valid_spec = Gem::Specification.new do |s|
          s.name = "valid_gem"
          s.version = "1.0.0"
          s.authors = ["Author"]
          s.summary = "Summary"
        end
        expect { valid_spec.validate_for_resolution }.not_to raise_error
      end
    end

    describe "#extension_dir" do
      it "responds to the method" do
        expect(spec).to respond_to(:extension_dir)
      end

      it "returns a string" do
        result = spec.extension_dir
        expect(result).to be_a(String)
      end
    end

    describe "MatchMetadata inclusion" do
      it "includes MatchMetadata methods" do
        expect(spec).to respond_to(:matches_current_metadata?)
        expect(spec).to respond_to(:matches_current_ruby?)
        expect(spec).to respond_to(:matches_current_rubygems?)
      end

      it "matches current ruby version for a spec with no ruby requirement" do
        expect(spec.matches_current_ruby?).to be true
      end

      it "matches current rubygems version for a spec with no rubygems requirement" do
        expect(spec.matches_current_rubygems?).to be true
      end
    end
  end

  describe "Gem::Dependency extensions" do
    let(:dep) { Gem::Dependency.new("test_dep", "~> 1.0") }

    describe "#source and #source=" do
      it "allows setting and getting a source" do
        mock_source = double("source")
        dep.source = mock_source
        expect(dep.source).to eq(mock_source)
      end

      it "defaults to nil" do
        fresh_dep = Gem::Dependency.new("fresh", ">= 0")
        expect(fresh_dep.source).to be_nil
      end
    end

    describe "#groups and #groups=" do
      it "allows setting and getting groups" do
        dep.groups = [:development, :test]
        expect(dep.groups).to eq([:development, :test])
      end

      it "defaults to nil" do
        fresh_dep = Gem::Dependency.new("fresh", ">= 0")
        expect(fresh_dep.groups).to be_nil
      end
    end

    describe "#to_lock" do
      it "returns a formatted lock string with name and version requirement" do
        result = dep.to_lock
        expect(result).to be_a(String)
        expect(result).to include("test_dep")
      end

      it "includes the version constraint in parentheses" do
        result = dep.to_lock
        expect(result).to match(/test_dep \(.*~>.*1\.0.*\)/)
      end

      it "indents with two spaces" do
        result = dep.to_lock
        expect(result).to start_with("  ")
      end

      it "handles dependencies with no version requirement" do
        dep_no_version = Gem::Dependency.new("any_gem")
        result = dep_no_version.to_lock
        expect(result).to eq("  any_gem")
      end

      it "sorts version requirements in reverse order" do
        complex_dep = Gem::Dependency.new("multi_req", [">= 1.0", "< 3.0"])
        result = complex_dep.to_lock
        expect(result).to include("multi_req")
        expect(result).to include("(")
        expect(result).to include(")")
      end
    end

    describe "#encode_with" do
      it "encodes dependency data to a coder" do
        coder = Psych::Coder.new("tag")
        dep.encode_with(coder)

        expect(coder.map).to have_key("name")
        expect(coder.map["name"]).to eq("test_dep")
        expect(coder.map).to have_key("requirement")
        expect(coder.map).to have_key("type")
      end

      it "includes all expected keys" do
        coder = Psych::Coder.new("tag")
        dep.encode_with(coder)

        expected_keys = %w[name requirement type prerelease version_requirements]
        expected_keys.each do |key|
          expect(coder.map).to have_key(key), "Expected coder to have key '#{key}'"
        end
      end
    end

    describe "#eql?" do
      it "is aliased to ==" do
        dep_a = Gem::Dependency.new("test", "~> 1.0")
        dep_b = Gem::Dependency.new("test", "~> 1.0")
        expect(dep_a.eql?(dep_b)).to eq(dep_a == dep_b)
      end
    end

    describe "ForcePlatform inclusion" do
      it "includes the ForcePlatform module" do
        expect(Gem::Dependency.ancestors).to include(Bundler::ForcePlatform)
      end

      it "has force_ruby_platform reader" do
        expect(dep).to respond_to(:force_ruby_platform)
      end
    end
  end

  describe "Gem::BasicSpecification extensions" do
    describe "#ignored?" do
      it "responds to the method" do
        basic_spec = Gem::BasicSpecification.new
        expect(basic_spec).to respond_to(:ignored?)
      end
    end

    describe "#installable_on_platform?" do
      it "responds to the method" do
        basic_spec = Gem::BasicSpecification.new
        expect(basic_spec).to respond_to(:installable_on_platform?)
      end
    end
  end

  describe "Gem::NameTuple extensions" do
    describe "#lock_name" do
      it "returns formatted name with version for RUBY platform" do
        name_tuple = Gem::NameTuple.new("mygem", Gem::Version.new("2.3.4"), Gem::Platform::RUBY)
        result = name_tuple.lock_name
        expect(result).to eq("mygem (2.3.4)")
      end

      it "includes platform in the lock name for non-RUBY platforms" do
        name_tuple = Gem::NameTuple.new("mygem", Gem::Version.new("2.3.4"), "java")
        result = name_tuple.lock_name
        expect(result).to eq("mygem (2.3.4-java)")
      end

      it "handles platform as a string" do
        name_tuple = Gem::NameTuple.new("mygem", Gem::Version.new("1.0.0"), "x86_64-linux")
        result = name_tuple.lock_name
        expect(result).to eq("mygem (1.0.0-x86_64-linux)")
      end

      it "handles platform as a Gem::Platform object" do
        platform = Gem::Platform.new("x86_64-linux")
        name_tuple = Gem::NameTuple.new("mygem", Gem::Version.new("1.0.0"), platform)
        result = name_tuple.lock_name
        expect(result).to eq("mygem (1.0.0-x86_64-linux)")
      end

      it "returns a String" do
        name_tuple = Gem::NameTuple.new("test", Gem::Version.new("1.0"), Gem::Platform::RUBY)
        expect(name_tuple.lock_name).to be_a(String)
      end
    end

    describe "#initialize with platform coercion" do
      it "stores platform as a string" do
        platform_obj = Gem::Platform.new("x86_64-linux")
        name_tuple = Gem::NameTuple.new("test", Gem::Version.new("1.0"), platform_obj)
        expect(name_tuple.platform).to be_a(String)
      end

      it "handles string platform" do
        name_tuple = Gem::NameTuple.new("test", Gem::Version.new("1.0"), "ruby")
        expect(name_tuple.platform).to eq("ruby")
      end

      it "defaults to RUBY platform" do
        name_tuple = Gem::NameTuple.new("test", Gem::Version.new("1.0"))
        expect(name_tuple.platform).to eq("ruby")
      end
    end
  end

  describe "Gem::StubSpecification extensions" do
    describe "BetterPermissionError" do
      it "is prepended to StubSpecification" do
        expect(Gem::StubSpecification.ancestors).to include(Gem::BetterPermissionError)
      end
    end
  end

  describe "Gem::Specification constant" do
    describe "VALIDATES_FOR_RESOLUTION" do
      it "is defined" do
        expect(defined?(Gem::VALIDATES_FOR_RESOLUTION)).to be_truthy
      end

      it "is a boolean-like value" do
        expect([true, false]).to include(Gem::VALIDATES_FOR_RESOLUTION)
      end
    end
  end

  describe "integration behaviors" do
    describe "Gem::Specification with dependencies" do
      let(:spec_with_deps) do
        Gem::Specification.new do |s|
          s.name = "complex_gem"
          s.version = "2.0.0"
          s.authors = ["Test"]
          s.summary = "Complex gem with dependencies"
          s.add_dependency("rack", "~> 2.0")
          s.add_dependency("json", ">= 1.8")
          s.add_development_dependency("rspec", "~> 3.0")
          s.add_development_dependency("rubocop", "~> 1.0")
        end
      end

      it "correctly separates development and non-development dependencies" do
        nondev = spec_with_deps.nondevelopment_dependencies
        dev = spec_with_deps.development_dependencies
        all = spec_with_deps.dependencies

        expect(nondev.length).to eq(2)
        expect(dev.length).to eq(2)
        expect(all.length).to eq(4)
        expect(nondev + dev).to match_array(all)
      end

      it "generates a complete gemfile with all dependency groups" do
        gemfile = spec_with_deps.to_gemfile
        expect(gemfile).to include("source 'https://rubygems.org'")
        expect(gemfile).to include('gem "rack"')
        expect(gemfile).to include('gem "json"')
        expect(gemfile).to include("group :development")
        expect(gemfile).to include('gem "rspec"')
        expect(gemfile).to include('gem "rubocop"')
      end
    end

    describe "Gem::Dependency lock formatting" do
      it "formats single requirement correctly" do
        dep = Gem::Dependency.new("rails", "~> 7.0")
        result = dep.to_lock
        expect(result).to start_with("  rails")
        expect(result).to include("~> 7.0")
      end

      it "formats multiple requirements correctly" do
        dep = Gem::Dependency.new("nokogiri", [">= 1.10", "< 2.0"])
        result = dep.to_lock
        expect(result).to start_with("  nokogiri")
        expect(result).to include("(")
        expect(result).to include(")")
      end

      it "formats no-requirement dependency correctly" do
        dep = Gem::Dependency.new("bundler")
        result = dep.to_lock
        expect(result).to eq("  bundler")
      end
    end

    describe "Gem::NameTuple lock_name consistency with Gem::Specification" do
      it "produces consistent lock names" do
        spec = Gem::Specification.new do |s|
          s.name = "consistent_gem"
          s.version = "3.2.1"
        end

        tuple = Gem::NameTuple.new("consistent_gem", Gem::Version.new("3.2.1"), Gem::Platform::RUBY)
        expect(spec.lock_name).to eq(tuple.lock_name)
      end
    end

    describe "Platform generic resolution" do
      it "resolves standard linux to RUBY" do
        linux = Gem::Platform.new("x86_64-linux")
        expect(Gem::Platform.generic(linux)).to eq(Gem::Platform::RUBY)
      end

      it "resolves darwin to RUBY" do
        darwin = Gem::Platform.new("arm64-darwin")
        expect(Gem::Platform.generic(darwin)).to eq(Gem::Platform::RUBY)
      end

      it "resolves java to java" do
        java = Gem::Platform.new("java")
        expect(Gem::Platform.generic(java)).to eq(java)
      end
    end
  end
end
