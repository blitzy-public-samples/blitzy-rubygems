# frozen_string_literal: true

require "spec_helper"
require "bundler/compact_index_client"
require "tmpdir"

RSpec.describe Bundler::CompactIndexClient do
  # Use a dedicated temp directory for each test to isolate cache state.
  # The Cache constructor creates subdirectories (info/, info-special-characters/, info-etags/),
  # so we provide a clean root for each example.
  let(:tmpdir) { Dir.mktmpdir("compact_index_client_spec") }
  let(:directory) { tmpdir }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  describe "constants" do
    it "defines SUPPORTED_DIGESTS as a frozen hash with sha-256 mapped to SHA256" do
      expect(described_class::SUPPORTED_DIGESTS).to be_a(Hash)
      expect(described_class::SUPPORTED_DIGESTS).to be_frozen
      expect(described_class::SUPPORTED_DIGESTS["sha-256"]).to eq(:SHA256)
    end

    it "defines DEBUG_MUTEX as a Thread::Mutex instance" do
      expect(described_class::DEBUG_MUTEX).to be_a(Thread::Mutex)
      expect(described_class::DEBUG_MUTEX).to respond_to(:synchronize)
    end

    it "defines INFO index constants for positional array access" do
      expect(described_class::INFO_NAME).to eq(0)
      expect(described_class::INFO_VERSION).to eq(1)
      expect(described_class::INFO_PLATFORM).to eq(2)
      expect(described_class::INFO_DEPS).to eq(3)
      expect(described_class::INFO_REQS).to eq(4)
    end
  end

  # ---------------------------------------------------------------------------
  # Error class
  # ---------------------------------------------------------------------------
  describe "::Error" do
    it "inherits from StandardError and can carry a message" do
      expect(described_class::Error).to be < StandardError
      error = described_class::Error.new("compact index failure")
      expect(error.message).to eq("compact index failure")
    end

    it "can be raised and rescued with the correct message" do
      error = described_class::Error.new("something went wrong")
      expect(error).to be_a(StandardError)
      expect {
        raise described_class::Error, "something went wrong"
      }.to raise_error(described_class::Error, "something went wrong")
    end
  end

  # ---------------------------------------------------------------------------
  # .debug class method
  # ---------------------------------------------------------------------------
  describe ".debug" do
    context "when DEBUG_COMPACT_INDEX env var is not set" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("DEBUG_COMPACT_INDEX").and_return(nil)
      end

      it "does not output anything and returns nil" do
        expect {
          result = described_class.debug { "should not appear" }
          expect(result).to be_nil
        }.not_to output.to_stderr
      end
    end

    context "when DEBUG_COMPACT_INDEX env var is set" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("DEBUG_COMPACT_INDEX").and_return("1")
      end

      it "outputs the block value to stderr including the class name" do
        expect {
          described_class.debug { "test debug output" }
        }.to output(/CompactIndexClient.*test debug output/).to_stderr
        expect(described_class).to respond_to(:debug)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # #initialize
  # ---------------------------------------------------------------------------
  describe "#initialize" do
    it "accepts a directory path and creates a client instance" do
      client = described_class.new(directory)
      expect(client).to be_a(described_class)
      expect(client).to respond_to(:names)
    end

    it "accepts a directory path and an optional fetcher" do
      fetcher = double("fetcher", call: nil)
      client = described_class.new(directory, fetcher)
      expect(client).to be_a(described_class)
      expect(client).to respond_to(:versions)
    end

    it "internally creates Cache and Parser components" do
      client = described_class.new(directory)
      # Verify the client exposes the full public API built on top of Cache/Parser
      expect(client).to respond_to(:names, :versions, :info, :dependencies,
                                   :latest_version, :available?, :reset!)
      expect(client).to be_a(described_class)
    end
  end

  # ---------------------------------------------------------------------------
  # Integration tests — populated cache files (no fetcher, local-only reads)
  # ---------------------------------------------------------------------------
  context "with populated cache files" do
    # Pre-populate the directory structure that Cache expects on construction.
    # Cache#initialize calls mkdir for info/, info-special-characters/, info-etags/.
    # Since we instantiate the client (which creates Cache), the dirs are auto-created.
    # We write the cache data files *before* creating the client so the first read succeeds.

    let(:names_content) { "---\nalpha\nbeta\ngamma\n" }
    let(:versions_content) { "---\nalpha 1.0.0 abc123\nbeta 2.0.0,2.1.0 def456\n" }
    let(:info_alpha_content) { "1.0.0 depx:>= 0|checksum:abc123" }
    let(:info_beta_content) { "2.0.0 |checksum:def\n2.1.0 depy:~> 1.0|checksum:ghi" }

    before do
      # Manually create directory structure and files before client instantiation.
      # Cache constructor will create the subdirs via mkdir, but we need the data
      # files present on disk so that Cache#read finds them.
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))

      File.write(File.join(directory, "names"), names_content)
      File.write(File.join(directory, "versions"), versions_content)
      File.write(File.join(directory, "info", "alpha"), info_alpha_content)
      File.write(File.join(directory, "info", "beta"), info_beta_content)
    end

    let(:client) { described_class.new(directory) }

    # ---- #names ----
    describe "#names" do
      it "returns an array of gem names parsed from the names file" do
        result = client.names
        expect(result).to be_a(Array)
        expect(result).to contain_exactly("alpha", "beta", "gamma")
      end

      it "strips the --- header line from the returned list" do
        result = client.names
        expect(result).not_to include("---")
        expect(result.length).to eq(3)
      end
    end

    # ---- #versions ----
    describe "#versions" do
      it "returns a hash keyed by gem name with version arrays as values" do
        result = client.versions
        expect(result).to be_a(Hash)
        expect(result.keys).to include("alpha", "beta")
      end

      it "parses individual version entries for each gem" do
        result = client.versions
        expect(result["alpha"]).to be_a(Array)
        expect(result["alpha"]).not_to be_empty
        expect(result["beta"].length).to eq(2)
      end
    end

    # ---- #info ----
    describe "#info" do
      it "returns an array of info arrays for the requested gem" do
        result = client.info("alpha")
        expect(result).to be_a(Array)
        expect(result).not_to be_empty
      end

      it "places the gem name at INFO_NAME index in each entry" do
        result = client.info("alpha")
        entry = result.first
        expect(entry[described_class::INFO_NAME]).to eq("alpha")
        expect(entry[described_class::INFO_VERSION]).to eq("1.0.0")
      end

      it "parses dependency information at INFO_DEPS index" do
        result = client.info("alpha")
        deps = result.first[described_class::INFO_DEPS]
        expect(deps).to be_a(Array)
        expect(deps).not_to be_empty
      end

      it "returns multiple entries for gems with multiple versions" do
        result = client.info("beta")
        expect(result.length).to eq(2)
        versions = result.map { |e| e[described_class::INFO_VERSION] }
        expect(versions).to include("2.0.0", "2.1.0")
      end

      it "returns an empty array when the info file does not exist" do
        result = client.info("nonexistent")
        expect(result).to be_a(Array)
        expect(result).to be_empty
      end
    end

    # ---- #dependencies ----
    describe "#dependencies" do
      it "maps each requested name to its info result" do
        result = client.dependencies(["alpha", "beta"])
        expect(result).to be_a(Array)
        expect(result.length).to eq(2)
      end

      it "returns info arrays for each name in the same order" do
        result = client.dependencies(["beta", "alpha"])
        # First element is beta's info, second is alpha's info
        expect(result.first.first[described_class::INFO_NAME]).to eq("beta")
        expect(result.last.first[described_class::INFO_NAME]).to eq("alpha")
      end

      it "returns an empty array when given an empty names list" do
        result = client.dependencies([])
        expect(result).to be_a(Array)
        expect(result).to be_empty
      end
    end

    # ---- #latest_version ----
    describe "#latest_version" do
      it "returns a Gem::Version representing the highest version" do
        result = client.latest_version("beta")
        expect(result).to be_a(Gem::Version)
        expect(result).to eq(Gem::Version.new("2.1.0"))
      end

      it "returns the correct version when only one version exists" do
        result = client.latest_version("alpha")
        expect(result).to be_a(Gem::Version)
        expect(result).to eq(Gem::Version.new("1.0.0"))
      end
    end

    # ---- #available? ----
    describe "#available?" do
      it "returns true when versions data has been parsed" do
        # Trigger versions parsing to populate info_checksums
        client.versions
        result = client.available?
        expect(result).to be true
        expect(result).to eq(true)
      end

      it "returns true even without explicitly calling versions first if versions file exists" do
        # available? internally calls info_checksums which reads the versions file
        result = client.available?
        expect(result).to be true
        expect(result).to eq(true)
      end
    end

    # ---- #reset! ----
    describe "#reset!" do
      it "does not raise an error when called" do
        expect { client.reset! }.not_to raise_error
        expect(client).to be_a(described_class)
      end

      it "clears the fetch cache so subsequent reads re-fetch from disk" do
        # First read
        first_names = client.names
        # Reset the cache endpoint tracking
        client.reset!
        # Read again — should still return data from the unchanged files
        second_names = client.names
        expect(first_names).to eq(second_names)
        expect(second_names).to contain_exactly("alpha", "beta", "gamma")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Empty directory — edge cases
  # ---------------------------------------------------------------------------
  context "with empty directory" do
    let(:client) { described_class.new(directory) }

    describe "#names" do
      it "returns an empty array when no names file exists" do
        result = client.names
        expect(result).to be_a(Array)
        expect(result).to be_empty
      end
    end

    describe "#versions" do
      it "returns an empty hash when no versions file exists" do
        result = client.versions
        expect(result).to be_a(Hash)
        expect(result).to be_empty
      end
    end

    describe "#available?" do
      it "returns false when no versions data exists" do
        expect(client.available?).to be false
        expect(client.available?).to eq(false)
      end
    end

    describe "#dependencies" do
      it "returns empty info arrays for each requested name" do
        result = client.dependencies(["nonexistent_gem"])
        expect(result).to be_a(Array)
        expect(result.length).to eq(1)
        expect(result.first).to be_empty
      end
    end

    describe "#latest_version" do
      it "returns nil when the info file does not exist" do
        result = client.latest_version("missing")
        expect(result).to be_nil
        expect(result).to eq(nil)
      end
    end

    describe "#reset!" do
      it "can be called safely on a fresh client" do
        expect { client.reset! }.not_to raise_error
        expect(client.names).to be_empty
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Multiple versions of the same gem
  # ---------------------------------------------------------------------------
  context "with multiple versions of the same gem" do
    let(:client) { described_class.new(directory) }

    before do
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))

      # Versions file listing three versions comma-separated
      File.write(File.join(directory, "versions"), "---\nmultiver 0.9.0,1.0.0,2.0.0 checksum789\n")

      # Info file with three version lines
      info_lines = [
        "0.9.0 |checksum:aaa",
        "1.0.0 dep_a:>= 1.0|checksum:bbb",
        "2.0.0 dep_a:>= 1.0,dep_b:~> 3.0|checksum:ccc",
      ].join("\n")
      File.write(File.join(directory, "info", "multiver"), info_lines)
    end

    describe "#versions" do
      it "records all three version entries for the gem" do
        result = client.versions
        expect(result["multiver"]).to be_a(Array)
        expect(result["multiver"].length).to eq(3)
      end
    end

    describe "#info" do
      it "returns info entries for every version" do
        result = client.info("multiver")
        expect(result.length).to eq(3)
        versions = result.map { |e| e[described_class::INFO_VERSION] }
        expect(versions).to contain_exactly("0.9.0", "1.0.0", "2.0.0")
      end
    end

    describe "#latest_version" do
      it "returns the maximum version as a Gem::Version" do
        result = client.latest_version("multiver")
        expect(result).to eq(Gem::Version.new("2.0.0"))
        expect(result).to be > Gem::Version.new("1.0.0")
      end
    end

    describe "#dependencies" do
      it "returns all version info when requesting the gem by name" do
        result = client.dependencies(["multiver"])
        expect(result.length).to eq(1)
        expect(result.first.length).to eq(3)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Version deletion markers (yanked versions)
  # ---------------------------------------------------------------------------
  context "with version deletion markers" do
    let(:client) { described_class.new(directory) }

    before do
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))

      # The compact index versions format uses a leading '-' to indicate a yanked version.
      # Parser#versions deletes the matching entry from the version list.
      versions_data = "---\nyanked_gem 1.0.0,2.0.0,-1.0.0 chk123\n"
      File.write(File.join(directory, "versions"), versions_data)

      File.write(File.join(directory, "info", "yanked_gem"), "2.0.0 |checksum:xyz")
    end

    describe "#versions" do
      it "removes the yanked version from the listing" do
        result = client.versions
        version_strings = result["yanked_gem"].map { |v| v[1] }
        expect(version_strings).to include("2.0.0")
        expect(version_strings).not_to include("1.0.0")
      end

      it "retains only the non-yanked versions" do
        result = client.versions
        expect(result["yanked_gem"].length).to eq(1)
        expect(result["yanked_gem"].first[1]).to eq("2.0.0")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Platform-specific versions
  # ---------------------------------------------------------------------------
  context "with platform-specific versions" do
    let(:client) { described_class.new(directory) }

    before do
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))

      # Platform is appended to version with a dash, e.g. "1.0.0-java"
      File.write(File.join(directory, "versions"), "---\nplatgem 1.0.0-java,1.0.0 chkplat\n")
      File.write(File.join(directory, "info", "platgem"),
                 "1.0.0-java |checksum:p1\n1.0.0 |checksum:p2")
    end

    describe "#versions" do
      it "includes platform-specific version entries" do
        result = client.versions
        expect(result["platgem"]).to be_a(Array)
        expect(result["platgem"].length).to eq(2)
      end
    end

    describe "#info" do
      it "distinguishes platform-specific entries by INFO_PLATFORM index" do
        result = client.info("platgem")
        expect(result.length).to eq(2)
        platforms = result.map { |e| e[described_class::INFO_PLATFORM] }
        expect(platforms).to include("java")
      end

      it "includes an entry without a platform" do
        result = client.info("platgem")
        platforms = result.map { |e| e[described_class::INFO_PLATFORM] }
        expect(platforms).to include(nil)
        expect(result.length).to eq(2)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Index parsing — verifying compact index data format handling
  # ---------------------------------------------------------------------------
  context "index parsing" do
    let(:client) { described_class.new(directory) }

    before do
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))
    end

    it "skips content before the --- header in names" do
      File.write(File.join(directory, "names"), "created_at: 2024-01-01\n---\ngem_a\ngem_b\n")
      result = client.names
      expect(result).to contain_exactly("gem_a", "gem_b")
      expect(result).not_to include("created_at: 2024-01-01")
    end

    it "handles names file without a header separator" do
      File.write(File.join(directory, "names"), "gem_x\ngem_y\n")
      result = client.names
      expect(result).to include("gem_x")
      expect(result).to include("gem_y")
    end

    it "handles versions file with checksum column" do
      File.write(File.join(directory, "versions"), "---\nfoo 1.0.0 abc123\nbar 2.0.0 def456\n")
      result = client.versions
      expect(result.keys).to include("foo", "bar")
      expect(result["foo"]).not_to be_empty
    end

    it "parses info lines with dependencies and requirements separated by pipe" do
      File.write(File.join(directory, "info", "parsegem"),
                 "3.0.0 depx:>= 1.0,depy:~> 2.0|ruby:>= 2.7")
      File.write(File.join(directory, "versions"), "---\nparsegem 3.0.0 chk\n")
      result = client.info("parsegem")
      expect(result.length).to eq(1)
      entry = result.first
      expect(entry[described_class::INFO_NAME]).to eq("parsegem")
      expect(entry[described_class::INFO_VERSION]).to eq("3.0.0")
    end

    it "returns empty arrays for info lines with no dependencies" do
      File.write(File.join(directory, "info", "nodeps"), "1.0.0 |")
      File.write(File.join(directory, "versions"), "---\nnodeps 1.0.0 chk\n")
      result = client.info("nodeps")
      entry = result.first
      expect(entry[described_class::INFO_DEPS]).to be_a(Array)
      expect(entry[described_class::INFO_DEPS]).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Endpoint URL construction — verifying cache file paths
  # ---------------------------------------------------------------------------
  context "endpoint URL construction" do
    # The Cache class translates logical endpoints (names, versions, info/<name>)
    # into file paths under the cache directory. We verify that the expected files
    # are read by the client by placing data at the expected paths.

    let(:client) { described_class.new(directory) }

    before do
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))
    end

    it "reads names from the 'names' file in the cache directory" do
      File.write(File.join(directory, "names"), "---\nendpoint_gem\n")
      result = client.names
      expect(result).to include("endpoint_gem")
      expect(result.length).to eq(1)
    end

    it "reads versions from the 'versions' file in the cache directory" do
      File.write(File.join(directory, "versions"), "---\nep_gem 4.0.0 epchk\n")
      result = client.versions
      expect(result.keys).to include("ep_gem")
      expect(result["ep_gem"]).not_to be_empty
    end

    it "reads info from 'info/<name>' file in the cache directory" do
      File.write(File.join(directory, "versions"), "---\ninfo_target 1.0.0 ichk\n")
      File.write(File.join(directory, "info", "info_target"), "1.0.0 |checksum:ic")
      result = client.info("info_target")
      expect(result).not_to be_empty
      expect(result.first[described_class::INFO_NAME]).to eq("info_target")
    end
  end

  # ---------------------------------------------------------------------------
  # Nested class definitions — verifying inner classes are accessible
  # ---------------------------------------------------------------------------
  describe "nested classes" do
    it "defines Cache as a class" do
      expect(described_class::Cache).to be_a(Class)
      expect(described_class::Cache.instance_methods).to include(:names)
    end

    it "defines CacheFile as a class" do
      expect(described_class::CacheFile).to be_a(Class)
      expect(described_class::CacheFile).to respond_to(:write)
    end

    it "defines Parser as a class" do
      expect(described_class::Parser).to be_a(Class)
      expect(described_class::Parser.instance_methods).to include(:names)
    end

    it "defines Updater as a class" do
      expect(described_class::Updater).to be_a(Class)
      expect(described_class::Updater.instance_methods).to include(:update)
    end
  end

  # ---------------------------------------------------------------------------
  # Thread safety
  # ---------------------------------------------------------------------------
  describe "thread safety" do
    it "provides a DEBUG_MUTEX that can synchronize blocks" do
      mutex = described_class::DEBUG_MUTEX
      expect(mutex).to respond_to(:synchronize)
      result = mutex.synchronize { 99 }
      expect(result).to eq(99)
    end
  end

  # ---------------------------------------------------------------------------
  # Fetcher integration — using a double to verify fetcher is passed to Cache
  # ---------------------------------------------------------------------------
  context "with a fetcher double" do
    it "passes the fetcher to Cache for remote update capability" do
      fetcher = double("fetcher")
      # Creating the client with a fetcher should not raise — the fetcher is
      # stored by Cache's Updater for later use.
      client = described_class.new(directory, fetcher)
      expect(client).to be_a(described_class)
      expect(client).to respond_to(:names)
    end

    it "creates a client that supports the full public API when a fetcher is given" do
      fetcher = double("fetcher")
      client = described_class.new(directory, fetcher)
      # Verify the full API surface is available with a fetcher-backed client
      expect(client).to respond_to(:names, :versions, :info, :dependencies,
                                   :latest_version, :available?, :reset!)
      expect(client).to be_a(described_class)
    end
  end

  # ---------------------------------------------------------------------------
  # Edge case: names file with only header
  # ---------------------------------------------------------------------------
  context "with names file containing only the header" do
    let(:client) { described_class.new(directory) }

    before do
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))
      File.write(File.join(directory, "names"), "---\n")
    end

    it "returns an empty array when names file has only the separator" do
      result = client.names
      expect(result).to be_a(Array)
      expect(result).to be_empty
    end
  end

  # ---------------------------------------------------------------------------
  # Edge case: versions with empty checksum
  # ---------------------------------------------------------------------------
  context "with versions that have an empty checksum column" do
    let(:client) { described_class.new(directory) }

    before do
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))
      # Some compact index implementations may provide an empty checksum
      File.write(File.join(directory, "versions"), "---\nnochk 1.0.0 \n")
      File.write(File.join(directory, "info", "nochk"), "1.0.0 |")
    end

    it "still parses the version entry successfully" do
      result = client.versions
      expect(result["nochk"]).to be_a(Array)
      expect(result["nochk"]).not_to be_empty
    end

    it "can retrieve info for the gem" do
      result = client.info("nochk")
      expect(result).to be_a(Array)
      expect(result.first[described_class::INFO_NAME]).to eq("nochk")
    end
  end

  # ---------------------------------------------------------------------------
  # Edge case: calling methods repeatedly (idempotency)
  # ---------------------------------------------------------------------------
  context "repeated method calls" do
    let(:client) { described_class.new(directory) }

    before do
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))
      File.write(File.join(directory, "names"), "---\nrepeat_gem\n")
      File.write(File.join(directory, "versions"), "---\nrepeat_gem 1.0.0 rchk\n")
      File.write(File.join(directory, "info", "repeat_gem"), "1.0.0 |")
    end

    it "returns consistent results for multiple calls to #names" do
      first = client.names
      second = client.names
      expect(first).to eq(second)
      expect(first).to contain_exactly("repeat_gem")
    end

    it "returns consistent results for multiple calls to #versions" do
      first = client.versions
      second = client.versions
      expect(first.keys).to eq(second.keys)
      expect(first["repeat_gem"].length).to eq(second["repeat_gem"].length)
    end

    it "returns consistent results for multiple calls to #available?" do
      client.versions
      first = client.available?
      second = client.available?
      expect(first).to eq(true)
      expect(second).to eq(true)
    end
  end
end
