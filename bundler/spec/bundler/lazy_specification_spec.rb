# frozen_string_literal: true

require "spec_helper"
require "bundler/lazy_specification"

RSpec.describe Bundler::LazySpecification do
  let(:name)     { "foo" }
  let(:version)  { Gem::Version.new("1.0.0") }
  let(:platform) { Gem::Platform::RUBY }
  let(:source)   { double(:source) }

  subject { described_class.new(name, version, platform, source) }

  # ---------------------------------------------------------------------------
  # Module inclusions
  # ---------------------------------------------------------------------------
  describe "module inclusions" do
    it "includes MatchMetadata" do
      expect(described_class.ancestors).to include(Bundler::MatchMetadata)
    end

    it "includes MatchPlatform" do
      expect(described_class.ancestors).to include(Bundler::MatchPlatform)
    end

    it "includes ForcePlatform" do
      expect(described_class.ancestors).to include(Bundler::ForcePlatform)
    end
  end

  # ---------------------------------------------------------------------------
  # .new (initialization)
  # ---------------------------------------------------------------------------
  describe "#initialize" do
    it "sets name, version, and platform from arguments" do
      spec = described_class.new("bar", Gem::Version.new("2.0"), Gem::Platform::RUBY, source)
      expect(spec.name).to eq("bar")
      expect(spec.version).to eq(Gem::Version.new("2.0"))
      expect(spec.platform).to eq(Gem::Platform::RUBY)
    end

    it "defaults platform to Gem::Platform::RUBY when nil" do
      spec = described_class.new("bar", Gem::Version.new("2.0"), nil, source)
      expect(spec.platform).to eq(Gem::Platform::RUBY)
    end

    it "defaults dependencies to an empty array" do
      expect(subject.dependencies).to eq([])
      expect(subject.dependencies).to be_empty
    end

    it "defaults required_ruby_version to Gem::Requirement.default" do
      expect(subject.required_ruby_version).to eq(Gem::Requirement.default)
      expect(subject.required_ruby_version).to be_a(Gem::Requirement)
    end

    it "defaults required_rubygems_version to Gem::Requirement.default" do
      expect(subject.required_rubygems_version).to eq(Gem::Requirement.default)
      expect(subject.required_rubygems_version).to be_a(Gem::Requirement)
    end

    it "stores source from the argument" do
      expect(subject.source).to eq(source)
    end

    it "defaults most_specific_locked_platform to nil" do
      expect(subject.most_specific_locked_platform).to be_nil
    end

    it "defaults materialization to nil (unmaterialized)" do
      expect(subject.materialization).to be_nil
      expect(subject.incomplete?).to eq(true)
    end

    it "works without a source argument" do
      spec = described_class.new("bar", Gem::Version.new("1.0"), Gem::Platform::RUBY)
      expect(spec.source).to be_nil
      expect(spec.name).to eq("bar")
    end

    it "preserves an explicit non-ruby platform" do
      java_platform = Gem::Platform.new("java")
      spec = described_class.new("bar", Gem::Version.new("1.0"), java_platform, source)
      expect(spec.platform).to eq(java_platform)
      expect(spec.name).to eq("bar")
    end
  end

  # ---------------------------------------------------------------------------
  # .from_spec
  # ---------------------------------------------------------------------------
  describe ".from_spec" do
    let(:runtime_deps) { [Gem::Dependency.new("baz", "~> 1.0")] }
    let(:ruby_req)     { Gem::Requirement.new(">= 3.0") }
    let(:rubygems_req) { Gem::Requirement.new(">= 3.2") }
    let(:original_spec) do
      double(:spec,
        name: "bar",
        version: Gem::Version.new("2.5.0"),
        platform: Gem::Platform::RUBY,
        source: source,
        runtime_dependencies: runtime_deps,
        required_ruby_version: ruby_req,
        required_rubygems_version: rubygems_req)
    end

    it "creates a LazySpecification from another spec's attributes" do
      lazy = described_class.from_spec(original_spec)
      expect(lazy).to be_a(described_class)
      expect(lazy.name).to eq("bar")
      expect(lazy.version).to eq(Gem::Version.new("2.5.0"))
      expect(lazy.platform).to eq(Gem::Platform::RUBY)
    end

    it "copies runtime dependencies from the source spec" do
      lazy = described_class.from_spec(original_spec)
      expect(lazy.dependencies).to eq(runtime_deps)
      expect(lazy.dependencies.length).to eq(1)
    end

    it "copies required_ruby_version from the source spec" do
      lazy = described_class.from_spec(original_spec)
      expect(lazy.required_ruby_version).to eq(ruby_req)
    end

    it "copies required_rubygems_version from the source spec" do
      lazy = described_class.from_spec(original_spec)
      expect(lazy.required_rubygems_version).to eq(rubygems_req)
    end

    it "copies source from the source spec" do
      lazy = described_class.from_spec(original_spec)
      expect(lazy.source).to eq(source)
    end

    it "returns a new LazySpecification instance with materialization nil" do
      lazy = described_class.from_spec(original_spec)
      expect(lazy.materialization).to be_nil
      expect(lazy.incomplete?).to eq(true)
    end
  end

  # ---------------------------------------------------------------------------
  # #missing?
  # ---------------------------------------------------------------------------
  describe "#missing?" do
    it "returns false when materialization is nil (default state)" do
      expect(subject.missing?).to eq(false)
      expect(subject.materialization).to be_nil
    end

    it "returns true when materialization is self" do
      subject.instance_variable_set(:@materialization, subject)
      expect(subject.missing?).to eq(true)
    end

    it "returns false when materialization is some other object" do
      other = described_class.new("other", Gem::Version.new("2.0"), Gem::Platform::RUBY)
      subject.instance_variable_set(:@materialization, other)
      expect(subject.missing?).to eq(false)
    end
  end

  # ---------------------------------------------------------------------------
  # #incomplete?
  # ---------------------------------------------------------------------------
  describe "#incomplete?" do
    it "returns true when materialization is nil (default state)" do
      expect(subject.incomplete?).to eq(true)
      expect(subject.materialization).to be_nil
    end

    it "returns false when materialization is set to self (missing state)" do
      subject.instance_variable_set(:@materialization, subject)
      expect(subject.incomplete?).to eq(false)
    end

    it "returns false when materialization is set to another spec" do
      other = described_class.new("other", Gem::Version.new("2.0"), Gem::Platform::RUBY)
      subject.instance_variable_set(:@materialization, other)
      expect(subject.incomplete?).to eq(false)
    end
  end

  # ---------------------------------------------------------------------------
  # #source_changed?
  # ---------------------------------------------------------------------------
  describe "#source_changed?" do
    it "returns false when source has not been changed" do
      expect(subject.source_changed?).to eq(false)
      expect(subject.source).to eq(source)
    end

    it "returns true when source has been replaced" do
      new_source = double(:new_source)
      subject.source = new_source
      expect(subject.source_changed?).to eq(true)
    end

    it "returns false when source is re-assigned to the same object" do
      subject.source = source
      expect(subject.source_changed?).to eq(false)
    end
  end

  # ---------------------------------------------------------------------------
  # #full_name
  # ---------------------------------------------------------------------------
  describe "#full_name" do
    context "when platform is ruby" do
      it "returns name-version without platform suffix" do
        expect(subject.full_name).to eq("foo-1.0.0")
        expect(subject.full_name).not_to include("ruby")
      end
    end

    context "when platform is not ruby" do
      it "returns name-version-platform" do
        spec = described_class.new(name, version, Gem::Platform.new("x86_64-linux"), source)
        expect(spec.full_name).to eq("foo-1.0.0-x86_64-linux")
      end
    end

    context "when platform is nil (defaults to ruby)" do
      it "returns name-version without platform suffix" do
        spec = described_class.new(name, version, nil, source)
        expect(spec.full_name).to eq("foo-1.0.0")
      end
    end

    it "memoizes the result across calls" do
      first_call = subject.full_name
      second_call = subject.full_name
      expect(first_call).to equal(second_call)
    end
  end

  # ---------------------------------------------------------------------------
  # #lock_name
  # ---------------------------------------------------------------------------
  describe "#lock_name" do
    it "returns a string containing the gem name" do
      result = subject.lock_name
      expect(result).to be_a(String)
      expect(result).to include("foo")
    end

    it "returns consistent values on repeated calls (memoized)" do
      first_call = subject.lock_name
      second_call = subject.lock_name
      expect(first_call).to eq(second_call)
      expect(first_call).to equal(second_call)
    end
  end

  # ---------------------------------------------------------------------------
  # #name_tuple
  # ---------------------------------------------------------------------------
  describe "#name_tuple" do
    it "returns a Gem::NameTuple with name, version, and platform" do
      tuple = subject.name_tuple
      expect(tuple).to be_a(Gem::NameTuple)
      expect(tuple.name).to eq("foo")
      expect(tuple.version).to eq(Gem::Version.new("1.0.0"))
      expect(tuple.platform).to eq(Gem::Platform::RUBY)
    end

    context "with a non-ruby platform" do
      it "includes the platform in the name tuple" do
        java_platform = Gem::Platform.new("java")
        spec = described_class.new(name, version, java_platform, source)
        tuple = spec.name_tuple
        expect(tuple.platform).to eq("java")
        expect(tuple.name).to eq("foo")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #== (equality)
  # ---------------------------------------------------------------------------
  describe "#==" do
    it "returns true for specs with the same full_name" do
      other = described_class.new(name, version, platform)
      expect(subject == other).to eq(true)
    end

    it "returns false for specs with different names" do
      other = described_class.new("bar", version, platform)
      expect(subject == other).to eq(false)
    end

    it "returns false for specs with different versions" do
      other = described_class.new(name, Gem::Version.new("2.0.0"), platform)
      expect(subject == other).to eq(false)
    end

    it "returns false for specs with different platforms" do
      other = described_class.new(name, version, Gem::Platform.new("java"))
      expect(subject == other).to eq(false)
    end
  end

  # ---------------------------------------------------------------------------
  # #eql?
  # ---------------------------------------------------------------------------
  describe "#eql?" do
    it "returns true for specs with the same full_name" do
      other = described_class.new(name, version, platform)
      expect(subject.eql?(other)).to eq(true)
    end

    it "returns false for specs with different full_names" do
      other = described_class.new("bar", version, platform)
      expect(subject.eql?(other)).to eq(false)
    end
  end

  # ---------------------------------------------------------------------------
  # #hash
  # ---------------------------------------------------------------------------
  describe "#hash" do
    it "returns the same hash for equal specs" do
      other = described_class.new(name, version, platform)
      expect(subject.hash).to eq(other.hash)
    end

    it "can be used as a Hash key with equal specs mapping to the same entry" do
      other = described_class.new(name, version, platform)
      hash_map = { subject => "value" }
      expect(hash_map[other]).to eq("value")
    end

    it "returns different hashes for different specs" do
      other = described_class.new("bar", version, platform)
      expect(subject.hash).not_to eq(other.hash)
    end
  end

  # ---------------------------------------------------------------------------
  # #satisfies?
  # ---------------------------------------------------------------------------
  describe "#satisfies?" do
    it "returns true when dependency name and version match" do
      dep = Gem::Dependency.new("foo", ">= 0.5")
      expect(subject.satisfies?(dep)).to eq(true)
    end

    it "returns false when dependency name does not match" do
      dep = Gem::Dependency.new("bar", ">= 0.5")
      expect(subject.satisfies?(dep)).to eq(false)
    end

    it "returns false when version does not satisfy requirement" do
      dep = Gem::Dependency.new("foo", ">= 2.0")
      expect(subject.satisfies?(dep)).to eq(false)
    end

    it "handles default requirement with pre-release zero versions" do
      prerelease_spec = described_class.new("foo", Gem::Version.new("0.0.0.dev"), platform, source)
      dep = Gem::Dependency.new("foo")
      expect(prerelease_spec.satisfies?(dep)).to eq(true)
    end

    it "satisfies pessimistic version constraint within range" do
      dep = Gem::Dependency.new("foo", "~> 1.0")
      expect(subject.satisfies?(dep)).to eq(true)
    end

    it "rejects version outside pessimistic constraint range" do
      dep = Gem::Dependency.new("foo", "~> 2.0")
      expect(subject.satisfies?(dep)).to eq(false)
    end

    it "satisfies exact version match" do
      dep = Gem::Dependency.new("foo", "= 1.0.0")
      expect(subject.satisfies?(dep)).to eq(true)
    end

    it "does not satisfy mismatched exact version" do
      dep = Gem::Dependency.new("foo", "= 1.0.1")
      expect(subject.satisfies?(dep)).to eq(false)
    end

    it "satisfies combined requirements" do
      dep = Gem::Dependency.new("foo", [">= 0.5", "< 2.0"])
      expect(subject.satisfies?(dep)).to eq(true)
    end

    it "does not satisfy contradictory combined requirements" do
      dep = Gem::Dependency.new("foo", [">= 2.0", "< 3.0"])
      expect(subject.satisfies?(dep)).to eq(false)
    end
  end

  # ---------------------------------------------------------------------------
  # #to_lock
  # ---------------------------------------------------------------------------
  describe "#to_lock" do
    it "starts with the lock name indented by 4 spaces" do
      result = subject.to_lock
      expect(result).to start_with("    ")
      expect(result).to include(subject.lock_name)
    end

    it "includes runtime dependencies sorted and deduplicated" do
      dep1 = Gem::Dependency.new("baz", "~> 1.0")
      dep2 = Gem::Dependency.new("alpha", "~> 2.0")
      subject.dependencies = [dep1, dep2]

      result = subject.to_lock
      alpha_pos = result.index("alpha")
      baz_pos = result.index("baz")
      expect(alpha_pos).to be < baz_pos
    end

    it "excludes development dependencies from lock output" do
      runtime_dep = Gem::Dependency.new("baz", "~> 1.0", :runtime)
      dev_dep = Gem::Dependency.new("test_helper", "~> 1.0", :development)
      subject.dependencies = [runtime_dep, dev_dep]

      result = subject.to_lock
      expect(result).to include("baz")
      expect(result).not_to include("test_helper")
    end

    it "returns just the lock name line when there are no dependencies" do
      result = subject.to_lock
      lines = result.split("\n").reject(&:empty?)
      expect(lines.length).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # #runtime_dependencies
  # ---------------------------------------------------------------------------
  describe "#runtime_dependencies" do
    it "is aliased to dependencies and returns the same object" do
      deps = [Gem::Dependency.new("bar", "~> 1.0")]
      subject.dependencies = deps
      expect(subject.runtime_dependencies).to eq(deps)
      expect(subject.runtime_dependencies).to equal(subject.dependencies)
    end
  end

  # ---------------------------------------------------------------------------
  # #inspect
  # ---------------------------------------------------------------------------
  describe "#inspect" do
    it "returns a readable string with class name, spec name, and version info" do
      result = subject.inspect
      expect(result).to include("Bundler::LazySpecification")
      expect(result).to include("foo")
      expect(result).to include("1.0.0")
    end

    context "with a non-ruby platform" do
      it "includes the platform in the representation" do
        spec = described_class.new("bar", Gem::Version.new("3.0"), Gem::Platform.new("java"), source)
        result = spec.inspect
        expect(result).to include("bar")
        expect(result).to include("java")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #to_s
  # ---------------------------------------------------------------------------
  describe "#to_s" do
    it "returns the lock_name" do
      expect(subject.to_s).to eq(subject.lock_name)
      expect(subject.to_s).to be_a(String)
    end
  end

  # ---------------------------------------------------------------------------
  # #git_version
  # ---------------------------------------------------------------------------
  describe "#git_version" do
    context "when source is not a Git source" do
      it "returns nil" do
        allow(source).to receive(:is_a?).with(Bundler::Source::Git).and_return(false)
        expect(subject.git_version).to be_nil
      end
    end

    context "when source is a Git source" do
      let(:git_source) do
        double(:git_source, revision: "abc1234567890def")
      end

      it "returns truncated revision prefixed with a space" do
        spec = described_class.new(name, version, platform, git_source)
        allow(git_source).to receive(:is_a?) do |klass|
          klass == Bundler::Source::Git
        end
        result = spec.git_version
        expect(result).to eq(" abc1234")
        expect(result).to start_with(" ")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #force_ruby_platform!
  # ---------------------------------------------------------------------------
  describe "#force_ruby_platform!" do
    it "sets force_ruby_platform to true" do
      subject.force_ruby_platform!
      expect(subject.force_ruby_platform).to eq(true)
    end

    it "overrides any previous force_ruby_platform value" do
      subject.force_ruby_platform = false
      subject.force_ruby_platform!
      expect(subject.force_ruby_platform).to eq(true)
    end
  end

  # ---------------------------------------------------------------------------
  # #replace_source_with!
  # ---------------------------------------------------------------------------
  describe "#replace_source_with!" do
    let(:gemfile_source) { double(:gemfile_source) }

    context "when gemfile_source can lock the spec" do
      before { allow(gemfile_source).to receive(:can_lock?).with(subject).and_return(true) }

      it "replaces the source and returns true" do
        result = subject.replace_source_with!(gemfile_source)
        expect(result).to eq(true)
        expect(subject.source).to eq(gemfile_source)
      end

      it "causes source_changed? to return true" do
        subject.replace_source_with!(gemfile_source)
        expect(subject.source_changed?).to eq(true)
      end
    end

    context "when gemfile_source cannot lock the spec" do
      before { allow(gemfile_source).to receive(:can_lock?).with(subject).and_return(false) }

      it "does not replace the source and returns nil" do
        result = subject.replace_source_with!(gemfile_source)
        expect(result).to be_nil
        expect(subject.source).to eq(source)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Accessor behavior
  # ---------------------------------------------------------------------------
  describe "accessors" do
    it "allows setting and getting remote" do
      subject.remote = "https://rubygems.org"
      expect(subject.remote).to eq("https://rubygems.org")
    end

    it "allows setting and getting force_ruby_platform" do
      subject.force_ruby_platform = true
      expect(subject.force_ruby_platform).to eq(true)
    end

    it "allows setting and getting dependencies" do
      deps = [Gem::Dependency.new("x", "~> 1.0")]
      subject.dependencies = deps
      expect(subject.dependencies).to eq(deps)
    end

    it "allows setting and getting required_ruby_version" do
      req = Gem::Requirement.new(">= 3.1")
      subject.required_ruby_version = req
      expect(subject.required_ruby_version).to eq(req)
    end

    it "allows setting and getting required_rubygems_version" do
      req = Gem::Requirement.new(">= 3.4")
      subject.required_rubygems_version = req
      expect(subject.required_rubygems_version).to eq(req)
    end

    it "allows setting and getting most_specific_locked_platform" do
      plat = Gem::Platform.new("x86_64-linux")
      subject.most_specific_locked_platform = plat
      expect(subject.most_specific_locked_platform).to eq(plat)
    end

    it "allows setting and getting source" do
      new_src = double(:new_source)
      subject.source = new_src
      expect(subject.source).to eq(new_src)
    end
  end

  # ---------------------------------------------------------------------------
  # Lazy loading behavior
  # ---------------------------------------------------------------------------
  describe "lazy loading behavior" do
    it "starts unmaterialized with materialization as nil" do
      spec = described_class.new("lazy", Gem::Version.new("0.1"), Gem::Platform::RUBY)
      expect(spec.materialization).to be_nil
      expect(spec.incomplete?).to eq(true)
    end

    it "is not missing when unmaterialized" do
      spec = described_class.new("lazy", Gem::Version.new("0.1"), Gem::Platform::RUBY)
      expect(spec.missing?).to eq(false)
      expect(spec.incomplete?).to eq(true)
    end

    it "provides all identifier attributes even when unmaterialized" do
      spec = described_class.new("lazy", Gem::Version.new("0.1"), Gem::Platform::RUBY)
      expect(spec.name).to eq("lazy")
      expect(spec.version).to eq(Gem::Version.new("0.1"))
      expect(spec.full_name).to eq("lazy-0.1")
    end
  end

  # ---------------------------------------------------------------------------
  # Source association
  # ---------------------------------------------------------------------------
  describe "source association" do
    it "tracks original source separately from current source" do
      new_source = double(:new_source)
      subject.source = new_source
      expect(subject.source).to eq(new_source)
      expect(subject.source_changed?).to eq(true)
    end

    it "reports source unchanged when source is the same as original" do
      expect(subject.source).to eq(source)
      expect(subject.source_changed?).to eq(false)
    end

    it "allows remote to be set independently from source" do
      remote_uri = "https://rubygems.org"
      subject.remote = remote_uri
      expect(subject.remote).to eq(remote_uri)
      expect(subject.source).to eq(source)
    end
  end

  # ---------------------------------------------------------------------------
  # Platform handling
  # ---------------------------------------------------------------------------
  describe "platform handling" do
    it "defaults platform to Gem::Platform::RUBY when nil is provided" do
      spec = described_class.new("plat_test", Gem::Version.new("1.0"), nil)
      expect(spec.platform).to eq(Gem::Platform::RUBY)
    end

    it "preserves explicit non-ruby platform" do
      java_platform = Gem::Platform.new("java")
      spec = described_class.new("plat_test", Gem::Version.new("1.0"), java_platform)
      expect(spec.platform).to eq(java_platform)
    end

    it "includes platform in full_name for non-ruby platforms" do
      linux_platform = Gem::Platform.new("x86_64-linux")
      spec = described_class.new("plat_test", Gem::Version.new("1.0"), linux_platform)
      expect(spec.full_name).to eq("plat_test-1.0-x86_64-linux")
      expect(spec.full_name).to include("x86_64-linux")
    end

    it "omits platform from full_name for ruby platform" do
      spec = described_class.new("plat_test", Gem::Version.new("1.0"), Gem::Platform::RUBY)
      expect(spec.full_name).to eq("plat_test-1.0")
      expect(spec.full_name).not_to include("ruby")
    end

    it "includes platform in name_tuple" do
      java_platform = Gem::Platform.new("java")
      spec = described_class.new("plat_test", Gem::Version.new("1.0"), java_platform)
      tuple = spec.name_tuple
      expect(tuple.platform).to eq("java")
      expect(tuple).to be_a(Gem::NameTuple)
    end
  end

  # ---------------------------------------------------------------------------
  # Dependency management
  # ---------------------------------------------------------------------------
  describe "dependency management" do
    it "defaults to an empty array for dependencies" do
      spec = described_class.new("dep_test", Gem::Version.new("1.0"), Gem::Platform::RUBY)
      expect(spec.dependencies).to eq([])
      expect(spec.dependencies).to be_empty
    end

    it "allows dependencies to be set and retrieved" do
      deps = [Gem::Dependency.new("rack", "~> 2.0"), Gem::Dependency.new("json", ">= 1.0")]
      subject.dependencies = deps
      expect(subject.dependencies).to eq(deps)
      expect(subject.dependencies.length).to eq(2)
    end

    it "aliases runtime_dependencies to dependencies" do
      deps = [Gem::Dependency.new("sinatra", "~> 3.0")]
      subject.dependencies = deps
      expect(subject.runtime_dependencies).to equal(subject.dependencies)
    end
  end

  # ---------------------------------------------------------------------------
  # #installable_on_platform? (from MatchPlatform)
  # ---------------------------------------------------------------------------
  describe "#installable_on_platform?" do
    it "returns true when platform is RUBY (installable everywhere)" do
      expect(subject.installable_on_platform?(Gem::Platform.new("x86_64-linux"))).to eq(true)
    end

    it "returns true when platform matches the target" do
      spec = described_class.new(name, version, Gem::Platform.new("x86_64-linux"), source)
      expect(spec.installable_on_platform?(Gem::Platform.new("x86_64-linux"))).to eq(true)
    end

    it "returns false when platform does not match the target" do
      spec = described_class.new(name, version, Gem::Platform.new("java"), source)
      expect(spec.installable_on_platform?(Gem::Platform.new("x86_64-linux"))).to eq(false)
    end
  end

  # ---------------------------------------------------------------------------
  # #matches_current_metadata? (from MatchMetadata)
  # ---------------------------------------------------------------------------
  describe "#matches_current_metadata?" do
    it "returns true with default requirements" do
      expect(subject.matches_current_metadata?).to eq(true)
    end

    it "returns true when current Ruby version satisfies required version" do
      subject.required_ruby_version = Gem::Requirement.new(">= 3.0")
      expect(subject.matches_current_metadata?).to eq(true)
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------
  describe "edge cases" do
    context "with a spec having no source" do
      subject { described_class.new("nosource", Gem::Version.new("0.1"), Gem::Platform::RUBY) }

      it "full_name still works correctly" do
        expect(subject.full_name).to eq("nosource-0.1")
      end

      it "to_lock produces valid output" do
        result = subject.to_lock
        expect(result).to include(subject.lock_name)
      end

      it "source is nil" do
        expect(subject.source).to be_nil
      end

      it "source_changed? returns false when source was initially nil" do
        expect(subject.source_changed?).to eq(false)
      end
    end

    context "with special version strings" do
      it "handles pre-release versions" do
        spec = described_class.new("pre", Gem::Version.new("1.0.0.beta1"), Gem::Platform::RUBY, source)
        expect(spec.full_name).to eq("pre-1.0.0.beta1")
        expect(spec.version.prerelease?).to eq(true)
      end

      it "handles zero version" do
        spec = described_class.new("zero", Gem::Version.new("0"), Gem::Platform::RUBY, source)
        expect(spec.full_name).to eq("zero-0")
        expect(spec.version).to eq(Gem::Version.new("0"))
      end

      it "handles multi-segment version" do
        spec = described_class.new("multi", Gem::Version.new("1.2.3.4.5"), Gem::Platform::RUBY, source)
        expect(spec.full_name).to eq("multi-1.2.3.4.5")
        expect(spec.version).to eq(Gem::Version.new("1.2.3.4.5"))
      end
    end

    context "equality and hash consistency" do
      it "specs in a Set behave correctly based on eql? and hash" do
        spec1 = described_class.new("gem", Gem::Version.new("1.0"), Gem::Platform::RUBY)
        spec2 = described_class.new("gem", Gem::Version.new("1.0"), Gem::Platform::RUBY)
        set = [spec1, spec2].uniq
        expect(set.length).to eq(1)
      end

      it "different versions produce distinct set entries" do
        spec1 = described_class.new("gem", Gem::Version.new("1.0"), Gem::Platform::RUBY)
        spec2 = described_class.new("gem", Gem::Version.new("2.0"), Gem::Platform::RUBY)
        set = [spec1, spec2].uniq
        expect(set.length).to eq(2)
      end

      it "different platforms produce distinct set entries" do
        spec1 = described_class.new("gem", Gem::Version.new("1.0"), Gem::Platform::RUBY)
        spec2 = described_class.new("gem", Gem::Version.new("1.0"), Gem::Platform.new("java"))
        set = [spec1, spec2].uniq
        expect(set.length).to eq(2)
      end
    end

    context "to_lock with dependencies of mixed types" do
      it "only includes runtime dependencies in lock output" do
        runtime = Gem::Dependency.new("rack", "~> 2.0", :runtime)
        dev = Gem::Dependency.new("rspec", "~> 3.0", :development)
        subject.dependencies = [runtime, dev]

        lock_output = subject.to_lock
        expect(lock_output).to include("rack")
        expect(lock_output).not_to include("rspec")
      end
    end
  end
end
