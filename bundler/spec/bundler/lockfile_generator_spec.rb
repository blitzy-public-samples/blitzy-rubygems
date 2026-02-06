# frozen_string_literal: true

require "spec_helper"
require "bundler/lockfile_generator"

RSpec.describe Bundler::LockfileGenerator do
  # Build comprehensive definition doubles with all required collaborators.
  # Only external dependencies (definition and its collaborators) are doubled;
  # LockfileGenerator itself is always invoked directly — never stubbed.

  let(:bundler_version) { "2.5.6" }

  let(:source_lock_output) { "GEM\n  remote: https://rubygems.org/\n  specs:\n" }
  let(:spec_a_lock_output) { "    rake (13.1.0)\n" }
  let(:spec_b_lock_output) { "    rspec (3.12.0)\n" }

  let(:checksum_store_a) do
    store = double("checksum_store_a")
    allow(store).to receive(:to_lock).and_return("rake (13.1.0) sha256=abc123\n")
    store
  end

  let(:checksum_store_b) do
    store = double("checksum_store_b")
    allow(store).to receive(:to_lock).and_return("rspec (3.12.0) sha256=def456\n")
    store
  end

  let(:spec_source_a) do
    double("spec_source_a", checksum_store: checksum_store_a)
  end

  let(:spec_source_b) do
    double("spec_source_b", checksum_store: checksum_store_b)
  end

  let(:spec_a) do
    double("spec_a",
      full_name: "rake-13.1.0",
      name: "rake",
      to_lock: spec_a_lock_output,
      source: spec_source_a)
  end

  let(:spec_b) do
    double("spec_b",
      full_name: "rspec-3.12.0",
      name: "rspec",
      to_lock: spec_b_lock_output,
      source: spec_source_b)
  end

  let(:source) do
    src = double("source")
    allow(src).to receive(:to_lock).and_return(source_lock_output)
    allow(src).to receive(:can_lock?).with(spec_a).and_return(true)
    allow(src).to receive(:can_lock?).with(spec_b).and_return(true)
    src
  end

  let(:sources) do
    srcs = double("sources")
    allow(srcs).to receive(:lock_sources).and_return([source])
    srcs
  end

  let(:resolve) { [spec_a, spec_b] }

  let(:dep_a) do
    d = double("dep_a", to_s: "rake", name: "rake")
    allow(d).to receive(:to_lock).and_return("  rake")
    d
  end

  let(:dep_b) do
    d = double("dep_b", to_s: "rspec", name: "rspec")
    allow(d).to receive(:to_lock).and_return("  rspec")
    d
  end

  let(:dependencies) { [dep_a, dep_b] }
  let(:platforms) { [Gem::Platform::RUBY, "x86_64-linux"] }
  let(:locked_checksums) { true }
  let(:locked_ruby_version) { nil }

  let(:definition) do
    defn = double("definition")
    allow(defn).to receive(:sources).and_return(sources)
    allow(defn).to receive(:resolve).and_return(resolve)
    allow(defn).to receive(:platforms).and_return(platforms)
    allow(defn).to receive(:dependencies).and_return(dependencies)
    allow(defn).to receive(:locked_checksums).and_return(locked_checksums)
    allow(defn).to receive(:locked_ruby_version).and_return(locked_ruby_version)
    allow(defn).to receive(:bundler_version_to_lock).and_return(Gem::Version.new(bundler_version))
    defn
  end

  describe ".generate" do
    it "creates a generator and returns a non-empty lockfile string" do
      result = described_class.generate(definition)
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end

    it "returns output containing all mandatory sections" do
      result = described_class.generate(definition)
      expect(result).to include("PLATFORMS")
      expect(result).to include("DEPENDENCIES")
      expect(result).to include("BUNDLED WITH")
    end

    it "starts output with the first source lock header" do
      result = described_class.generate(definition)
      expect(result).to start_with(source_lock_output)
      expect(result).to include("GEM")
    end
  end

  describe "#initialize" do
    it "stores the definition and initializes an empty output string" do
      generator = described_class.new(definition)
      expect(generator.definition).to equal(definition)
      expect(generator.out).to eq("")
    end

    it "exposes definition and out via attr_readers" do
      generator = described_class.new(definition)
      expect(generator).to respond_to(:definition)
      expect(generator).to respond_to(:out)
    end
  end

  describe "#generate!" do
    subject(:generator) { described_class.new(definition) }

    it "returns a non-empty string as the lockfile content" do
      result = generator.generate!
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end

    it "includes all mandatory sections in the output" do
      result = generator.generate!
      expect(result).to include("PLATFORMS")
      expect(result).to include("DEPENDENCIES")
      expect(result).to include("BUNDLED WITH")
    end

    it "returns the same object as the out accessor" do
      result = generator.generate!
      expect(result).to equal(generator.out)
      expect(result).to be_a(String)
    end

    context "with locked ruby version present" do
      let(:locked_ruby_version) { double("ruby_version", to_s: "ruby 3.2.3p173") }

      it "includes RUBY VERSION section with the version string" do
        result = generator.generate!
        expect(result).to include("RUBY VERSION")
        expect(result).to include("ruby 3.2.3p173")
      end
    end

    context "without locked ruby version" do
      let(:locked_ruby_version) { nil }

      it "omits RUBY VERSION section while keeping other mandatory sections" do
        result = generator.generate!
        expect(result).not_to include("RUBY VERSION")
        expect(result).to include("BUNDLED WITH")
      end
    end
  end

  context "source header generation" do
    subject(:generator) { described_class.new(definition) }

    it "outputs source lock data at the start of the lockfile" do
      result = generator.generate!
      expect(result).to start_with(source_lock_output)
      expect(result).to include("specs:")
    end

    context "with multiple sources" do
      let(:second_source_lock) { "GIT\n  remote: https://github.com/example/repo.git\n  specs:\n" }
      let(:second_source) do
        src = double("second_source")
        allow(src).to receive(:to_lock).and_return(second_source_lock)
        allow(src).to receive(:can_lock?).with(spec_a).and_return(false)
        allow(src).to receive(:can_lock?).with(spec_b).and_return(false)
        src
      end

      let(:sources) do
        srcs = double("sources")
        allow(srcs).to receive(:lock_sources).and_return([source, second_source])
        srcs
      end

      it "includes both source headers in the output" do
        result = generator.generate!
        expect(result).to include(source_lock_output)
        expect(result).to include(second_source_lock)
      end

      it "places sources in the order provided by lock_sources" do
        result = generator.generate!
        first_pos = result.index("https://rubygems.org/")
        second_pos = result.index("https://github.com/example/repo.git")
        expect(first_pos).not_to be_nil
        expect(second_pos).not_to be_nil
        expect(first_pos).to be < second_pos
      end
    end
  end

  context "GEM section formatting" do
    subject(:generator) { described_class.new(definition) }

    it "includes spec lock output sorted by full_name" do
      result = generator.generate!
      rake_pos = result.index(spec_a_lock_output)
      rspec_pos = result.index(spec_b_lock_output)
      expect(rake_pos).not_to be_nil
      expect(rspec_pos).not_to be_nil
      expect(rake_pos).to be < rspec_pos
    end

    it "skips the bundler gem from spec output" do
      bundler_spec = double("bundler_spec",
        full_name: "bundler-2.5.6",
        name: "bundler",
        to_lock: "    bundler (2.5.6)\n",
        source: spec_source_a)
      allow(source).to receive(:can_lock?).with(bundler_spec).and_return(true)
      allow(definition).to receive(:resolve).and_return([spec_a, bundler_spec, spec_b])

      result = generator.generate!
      expect(result).not_to include("    bundler (2.5.6)")
      expect(result).to include(spec_a_lock_output)
    end

    it "includes all non-bundler specs in the output" do
      result = generator.generate!
      expect(result).to include(spec_a_lock_output)
      expect(result).to include(spec_b_lock_output)
    end
  end

  context "PLATFORMS section" do
    subject(:generator) { described_class.new(definition) }

    it "lists platforms sorted alphabetically under the PLATFORMS header" do
      result = generator.generate!
      platforms_section = result[result.index("PLATFORMS")..result.index("DEPENDENCIES")]
      ruby_pos = platforms_section.index("ruby")
      x86_pos = platforms_section.index("x86_64-linux")
      expect(ruby_pos).not_to be_nil
      expect(x86_pos).not_to be_nil
      expect(ruby_pos).to be < x86_pos
    end

    it "formats each platform with two-space indentation" do
      result = generator.generate!
      expect(result).to match(/^  ruby\n/)
      expect(result).to match(/^  x86_64-linux\n/)
    end

    context "with a single platform" do
      let(:platforms) { [Gem::Platform::RUBY] }

      it "outputs the single platform under PLATFORMS header" do
        result = generator.generate!
        expect(result).to include("PLATFORMS\n  ruby\n")
        expect(result).to include("PLATFORMS")
      end
    end
  end

  context "DEPENDENCIES section" do
    subject(:generator) { described_class.new(definition) }

    it "lists dependencies sorted by their to_s value" do
      result = generator.generate!
      deps_start = result.index("\nDEPENDENCIES\n")
      expect(deps_start).not_to be_nil
      deps_section = result[deps_start..]
      rake_pos = deps_section.index("rake")
      rspec_pos = deps_section.index("rspec")
      expect(rake_pos).to be < rspec_pos
    end

    it "appends newline after each dependency lock output" do
      result = generator.generate!
      expect(result).to include("  rake\n")
      expect(result).to include("  rspec\n")
    end

    context "with duplicate dependency names" do
      let(:dep_a_dup) do
        d = double("dep_a_dup", to_s: "rake", name: "rake")
        allow(d).to receive(:to_lock).and_return("  rake (>= 13.0)")
        d
      end

      let(:dependencies) { [dep_a, dep_a_dup, dep_b] }

      it "deduplicates dependencies by name keeping only the first occurrence" do
        result = generator.generate!
        deps_header = "\nDEPENDENCIES\n"
        deps_start = result.index(deps_header) + deps_header.length
        next_section = result.index(/\n[A-Z]/, deps_start)
        deps_only = next_section ? result[deps_start...next_section] : result[deps_start..]
        rake_lines = deps_only.lines.select { |l| l.strip.start_with?("rake") }
        expect(rake_lines.length).to eq(1)
        expect(deps_only).to include("rake")
      end
    end

    context "with empty dependency list" do
      let(:dependencies) { [] }

      it "outputs DEPENDENCIES header with no dependency entries beneath it" do
        result = generator.generate!
        expect(result).to include("\nDEPENDENCIES\n")
        # After DEPENDENCIES header, the next character should be a newline (start of next section)
        deps_end = result.index("\nDEPENDENCIES\n") + "\nDEPENDENCIES\n".length
        expect(result[deps_end]).to eq("\n")
      end
    end
  end

  context "BUNDLED WITH section" do
    subject(:generator) { described_class.new(definition) }

    it "includes the bundler version in the BUNDLED WITH section" do
      result = generator.generate!
      expect(result).to include("BUNDLED WITH")
      expect(result).to include(bundler_version)
    end

    it "formats the bundler version with three-space indentation" do
      result = generator.generate!
      expect(result).to include("BUNDLED WITH\n   #{bundler_version}\n")
      expect(result).to match(/BUNDLED WITH\n   \d+\.\d+\.\d+\n/)
    end
  end

  context "CHECKSUMS section" do
    subject(:generator) { described_class.new(definition) }

    context "when locked_checksums is truthy" do
      let(:locked_checksums) { true }

      it "includes CHECKSUMS section header and checksum data" do
        result = generator.generate!
        expect(result).to include("CHECKSUMS")
        expect(result).to include("sha256=")
      end

      it "lists checksums sorted alphabetically with two-space indentation" do
        result = generator.generate!
        checksums_match = result.match(/CHECKSUMS\n((?:  .+\n)+)/)
        expect(checksums_match).not_to be_nil
        checksum_lines = checksums_match[1].split("\n").map(&:strip)
        expect(checksum_lines).to eq(checksum_lines.sort)
      end
    end

    context "when locked_checksums is nil" do
      let(:locked_checksums) { nil }

      it "does not include CHECKSUMS section while keeping mandatory sections" do
        result = generator.generate!
        expect(result).not_to include("CHECKSUMS")
        expect(result).to include("BUNDLED WITH")
      end
    end

    context "when locked_checksums is false" do
      let(:locked_checksums) { false }

      it "does not include CHECKSUMS section but retains other sections" do
        result = generator.generate!
        expect(result).not_to include("CHECKSUMS")
        expect(result).to include("DEPENDENCIES")
      end
    end
  end

  context "section formatting via public interface" do
    subject(:generator) { described_class.new(definition) }

    it "sorts array-type section values alphabetically" do
      result = generator.generate!
      platforms_match = result.match(/PLATFORMS\n((?:  .+\n)+)/)
      expect(platforms_match).not_to be_nil
      platform_lines = platforms_match[1].split("\n").map(&:strip)
      expect(platform_lines).to eq(platform_lines.sort)
    end

    it "uses three-space indent for string-type section values" do
      result = generator.generate!
      expect(result).to match(/BUNDLED WITH\n   \d+\.\d+\.\d+\n/)
      expect(result).to include("   #{bundler_version}")
    end
  end

  context "full lockfile generation" do
    subject(:generator) { described_class.new(definition) }

    it "produces sections in the correct order" do
      result = generator.generate!
      source_pos = result.index("GEM")
      platforms_pos = result.index("PLATFORMS")
      deps_pos = result.index("DEPENDENCIES")
      bundled_pos = result.index("BUNDLED WITH")

      expect(source_pos).to be < platforms_pos
      expect(platforms_pos).to be < deps_pos
      expect(deps_pos).to be < bundled_pos
    end

    context "with all optional sections enabled" do
      let(:locked_checksums) { true }
      let(:locked_ruby_version) { double("ruby_version", to_s: "ruby 3.2.3p173") }

      it "includes every possible section in the lockfile" do
        result = generator.generate!
        expect(result).to include("GEM")
        expect(result).to include("PLATFORMS")
        expect(result).to include("DEPENDENCIES")
        expect(result).to include("CHECKSUMS")
        expect(result).to include("RUBY VERSION")
        expect(result).to include("BUNDLED WITH")
      end
    end

    context "with no optional sections" do
      let(:locked_checksums) { nil }
      let(:locked_ruby_version) { nil }

      it "omits optional sections while retaining all mandatory ones" do
        result = generator.generate!
        expect(result).not_to include("CHECKSUMS")
        expect(result).not_to include("RUBY VERSION")
        expect(result).to include("PLATFORMS")
        expect(result).to include("DEPENDENCIES")
        expect(result).to include("BUNDLED WITH")
      end
    end

    context "with no sources and no dependencies" do
      let(:sources) do
        srcs = double("sources")
        allow(srcs).to receive(:lock_sources).and_return([])
        srcs
      end
      let(:dependencies) { [] }
      let(:locked_checksums) { nil }

      it "still produces PLATFORMS, DEPENDENCIES header, and BUNDLED WITH" do
        result = generator.generate!
        expect(result).to include("PLATFORMS")
        expect(result).to include("DEPENDENCIES")
        expect(result).to include("BUNDLED WITH")
      end
    end
  end
end
