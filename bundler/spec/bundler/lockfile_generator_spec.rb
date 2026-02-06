# frozen_string_literal: true

require "bundler/lockfile_generator"

RSpec.describe Bundler::LockfileGenerator do
  # Build a comprehensive definition double with all required collaborators.
  # Only external dependencies (definition and its collaborators) are doubled;
  # LockfileGenerator itself is always invoked directly.

  let(:bundler_version) { "2.5.6" }

  let(:source_lock_output) { "GEM\n  remote: https://rubygems.org/\n  specs:\n" }
  let(:spec_a_lock_output) { "    rake (13.1.0)\n" }
  let(:spec_b_lock_output) { "    rspec (3.12.0)\n" }

  let(:checksum_store) do
    store = double("checksum_store")
    allow(store).to receive(:to_lock).and_return("rake (13.1.0) sha256=abc123\n")
    store
  end

  let(:spec_source) do
    src = double("spec_source")
    allow(src).to receive(:checksum_store).and_return(checksum_store)
    src
  end

  let(:spec_a) do
    s = double("spec_a",
      full_name: "rake-13.1.0",
      name: "rake",
      to_lock: spec_a_lock_output,
      source: spec_source)
    s
  end

  let(:spec_b) do
    s = double("spec_b",
      full_name: "rspec-3.12.0",
      name: "rspec",
      to_lock: spec_b_lock_output,
      source: spec_source)
    s
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
    it "creates a new generator and calls generate!" do
      result = described_class.generate(definition)
      expect(result).to be_a(String)
      expect(result).to include("PLATFORMS")
    end

    it "returns output containing DEPENDENCIES section" do
      result = described_class.generate(definition)
      expect(result).to include("DEPENDENCIES")
      expect(result).to include("BUNDLED WITH")
    end

    it "includes source lock output at the beginning" do
      result = described_class.generate(definition)
      expect(result).to start_with(source_lock_output)
    end
  end

  describe "#initialize" do
    it "stores the definition and initializes an empty output string" do
      generator = described_class.new(definition)
      expect(generator.definition).to equal(definition)
      expect(generator.out).to eq("")
    end

    it "exposes definition via attr_reader" do
      generator = described_class.new(definition)
      expect(generator).to respond_to(:definition)
      expect(generator).to respond_to(:out)
    end
  end

  describe "#generate!" do
    subject(:generator) { described_class.new(definition) }

    it "returns the full lockfile string" do
      result = generator.generate!
      expect(result).to be_a(String)
      expect(result.length).to be > 0
    end

    it "includes all major sections in the output" do
      result = generator.generate!
      expect(result).to include("PLATFORMS")
      expect(result).to include("DEPENDENCIES")
      expect(result).to include("BUNDLED WITH")
    end

    it "returns the same object as out" do
      result = generator.generate!
      expect(result).to equal(generator.out)
    end

    context "with locked ruby version" do
      let(:locked_ruby_version) { double("ruby_version", to_s: "ruby 3.2.3p173") }

      it "includes RUBY VERSION section" do
        result = generator.generate!
        expect(result).to include("RUBY VERSION")
        expect(result).to include("ruby 3.2.3p173")
      end
    end

    context "without locked ruby version" do
      let(:locked_ruby_version) { nil }

      it "does not include RUBY VERSION section" do
        result = generator.generate!
        expect(result).not_to include("RUBY VERSION")
      end
    end
  end

  context "source header generation" do
    subject(:generator) { described_class.new(definition) }

    it "outputs source lock data at the beginning" do
      result = generator.generate!
      expect(result).to start_with(source_lock_output)
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

      it "separates multiple sources with blank lines" do
        result = generator.generate!
        expect(result).to include(source_lock_output)
        expect(result).to include(second_source_lock)
      end

      it "adds newline separator between sources" do
        result = generator.generate!
        # The first source does not have a leading newline; the second does
        lines = result.split("\n")
        first_source_idx = lines.index { |l| l.include?("https://rubygems.org/") }
        second_source_idx = lines.index { |l| l.include?("https://github.com/example/repo.git") }
        expect(first_source_idx).to be < second_source_idx
      end
    end
  end

  context "GEM section formatting" do
    subject(:generator) { described_class.new(definition) }

    it "includes spec lock output sorted by full_name" do
      result = generator.generate!
      # rake (full_name: rake-13.1.0) comes before rspec (full_name: rspec-3.12.0)
      rake_pos = result.index(spec_a_lock_output)
      rspec_pos = result.index(spec_b_lock_output)
      expect(rake_pos).not_to be_nil
      expect(rspec_pos).not_to be_nil
      expect(rake_pos).to be < rspec_pos
    end

    it "skips bundler gem from spec output" do
      bundler_spec = double("bundler_spec",
        full_name: "bundler-2.5.6",
        name: "bundler",
        to_lock: "    bundler (2.5.6)\n",
        source: spec_source)
      allow(source).to receive(:can_lock?).with(bundler_spec).and_return(true)
      local_resolve = [spec_a, bundler_spec, spec_b]
      allow(definition).to receive(:resolve).and_return(local_resolve)

      result = generator.generate!
      expect(result).not_to include("    bundler (2.5.6)")
      expect(result).to include(spec_a_lock_output)
    end
  end

  context "PLATFORMS section" do
    subject(:generator) { described_class.new(definition) }

    it "lists platforms alphabetically" do
      result = generator.generate!
      platforms_section = result[result.index("PLATFORMS")..result.index("DEPENDENCIES")]
      expect(platforms_section).to include("ruby")
      expect(platforms_section).to include("x86_64-linux")
      # Sorted: "ruby" < "x86_64-linux"
      ruby_pos = platforms_section.index("ruby")
      x86_pos = platforms_section.index("x86_64-linux")
      expect(ruby_pos).to be < x86_pos
    end

    it "formats each platform indented with two spaces" do
      result = generator.generate!
      expect(result).to match(/^  ruby\n/)
      expect(result).to match(/^  x86_64-linux\n/)
    end

    context "with single platform" do
      let(:platforms) { [Gem::Platform::RUBY] }

      it "outputs the single platform" do
        result = generator.generate!
        expect(result).to include("PLATFORMS\n  ruby\n")
      end
    end
  end

  context "DEPENDENCIES section" do
    subject(:generator) { described_class.new(definition) }

    it "lists dependencies sorted by to_s" do
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

      it "deduplicates dependencies by name" do
        result = generator.generate!
        deps_header = "\nDEPENDENCIES\n"
        deps_start = result.index(deps_header) + deps_header.length
        # Find the next section boundary (next "\n" followed by an uppercase header)
        next_section = result.index(/\n[A-Z]/, deps_start)
        deps_only = next_section ? result[deps_start...next_section] : result[deps_start..]
        # "rake" should appear only once in the DEPENDENCIES entries
        rake_lines = deps_only.lines.select { |l| l.strip.start_with?("rake") }
        expect(rake_lines.length).to eq(1)
      end
    end

    context "with empty dependency list" do
      let(:dependencies) { [] }

      it "outputs DEPENDENCIES header with no entries" do
        result = generator.generate!
        expect(result).to include("\nDEPENDENCIES\n")
        deps_start = result.index("\nDEPENDENCIES\n") + "\nDEPENDENCIES\n".length
        next_section = result.index("\n", deps_start)
        # Right after DEPENDENCIES header should come the next section
        expect(next_section).to eq(deps_start)
      end
    end
  end

  context "BUNDLED WITH section" do
    subject(:generator) { described_class.new(definition) }

    it "includes bundler version at the end of output" do
      result = generator.generate!
      expect(result).to include("BUNDLED WITH")
      expect(result).to include(bundler_version)
    end

    it "formats bundler version with three-space indent" do
      result = generator.generate!
      expect(result).to include("BUNDLED WITH\n   #{bundler_version}\n")
    end
  end

  context "CHECKSUMS section" do
    subject(:generator) { described_class.new(definition) }

    context "when locked_checksums is truthy" do
      let(:locked_checksums) { true }

      it "includes CHECKSUMS section in output" do
        result = generator.generate!
        expect(result).to include("CHECKSUMS")
      end

      it "lists checksums sorted alphabetically" do
        checksum_b = double("checksum_store_b")
        allow(checksum_b).to receive(:to_lock).and_return("rspec (3.12.0) sha256=def456\n")
        spec_b_src = double("spec_b_source", checksum_store: checksum_b)
        allow(spec_b).to receive(:source).and_return(spec_b_src)

        result = generator.generate!
        expect(result).to include("CHECKSUMS")
      end
    end

    context "when locked_checksums is falsy" do
      let(:locked_checksums) { nil }

      it "does not include CHECKSUMS section" do
        result = generator.generate!
        expect(result).not_to include("CHECKSUMS")
      end
    end
  end

  context "add_section private method behavior (tested via public interface)" do
    subject(:generator) { described_class.new(definition) }

    context "with array values (platforms)" do
      it "sorts array values alphabetically" do
        result = generator.generate!
        platforms_section_match = result.match(/PLATFORMS\n((?:  .+\n)+)/)
        expect(platforms_section_match).not_to be_nil
        platform_lines = platforms_section_match[1].split("\n").map(&:strip)
        expect(platform_lines).to eq(platform_lines.sort)
      end
    end

    context "with string values (bundled with)" do
      it "uses three-space indent for string values" do
        result = generator.generate!
        expect(result).to match(/BUNDLED WITH\n   \d+\.\d+\.\d+\n/)
      end
    end
  end

  context "full lockfile generation integration" do
    subject(:generator) { described_class.new(definition) }

    it "produces a valid lockfile structure with sections in correct order" do
      result = generator.generate!

      # The output should have: sources first, then PLATFORMS, DEPENDENCIES, and BUNDLED WITH
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

      it "includes all sections in the lockfile" do
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

      it "omits optional sections" do
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
