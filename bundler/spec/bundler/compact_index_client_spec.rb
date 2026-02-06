# frozen_string_literal: true

require "bundler/compact_index_client"
require "tmpdir"

RSpec.describe Bundler::CompactIndexClient do
  let(:tmpdir) { Dir.mktmpdir("compact_index_test") }
  let(:directory) { tmpdir }

  after do
    FileUtils.rm_rf(tmpdir)
  end

  describe "constants" do
    it "defines SUPPORTED_DIGESTS as a frozen hash mapping sha-256 to SHA256" do
      expect(described_class::SUPPORTED_DIGESTS).to be_a(Hash)
      expect(described_class::SUPPORTED_DIGESTS).to be_frozen
      expect(described_class::SUPPORTED_DIGESTS["sha-256"]).to eq(:SHA256)
    end

    it "defines DEBUG_MUTEX as a Thread::Mutex" do
      expect(described_class::DEBUG_MUTEX).to be_a(Thread::Mutex)
    end

    it "defines INFO index constants for array access" do
      expect(described_class::INFO_NAME).to eq(0)
      expect(described_class::INFO_VERSION).to eq(1)
      expect(described_class::INFO_PLATFORM).to eq(2)
      expect(described_class::INFO_DEPS).to eq(3)
      expect(described_class::INFO_REQS).to eq(4)
    end
  end

  describe "::Error" do
    it "is a subclass of StandardError" do
      expect(described_class::Error).to be < StandardError
    end

    it "can be instantiated with a message" do
      error = described_class::Error.new("test error")
      expect(error.message).to eq("test error")
    end

    it "can be raised and rescued" do
      expect {
        raise described_class::Error, "compact index error"
      }.to raise_error(described_class::Error, "compact index error")
    end
  end

  describe ".debug" do
    context "when DEBUG_COMPACT_INDEX is not set" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("DEBUG_COMPACT_INDEX").and_return(nil)
      end

      it "does not output anything" do
        expect {
          described_class.debug { "test message" }
        }.not_to output.to_stderr
      end

      it "returns nil" do
        result = described_class.debug { "test message" }
        expect(result).to be_nil
      end
    end

    context "when DEBUG_COMPACT_INDEX is set" do
      before do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("DEBUG_COMPACT_INDEX").and_return("1")
      end

      it "outputs the debug message to stderr" do
        expect {
          described_class.debug { "test message" }
        }.to output(/test message/).to_stderr
      end

      it "includes the class name in the output" do
        expect {
          described_class.debug { "hello" }
        }.to output(/CompactIndexClient/).to_stderr
      end
    end
  end

  describe "#initialize" do
    it "creates a new instance with a directory and no fetcher" do
      client = described_class.new(directory)
      expect(client).to be_a(described_class)
    end

    it "creates a new instance with a directory and a fetcher" do
      fetcher = double(:fetcher)
      client = described_class.new(directory, fetcher)
      expect(client).to be_a(described_class)
    end
  end

  describe "integration with Cache and Parser" do
    # These tests use real Cache and Parser instances (no mocking of internal classes)
    # and set up local file fixtures to exercise the full flow through the production code.

    let(:names_content) { "---\nfoo\nbar\nbaz\n" }
    let(:versions_content) { "---\nfoo 1.0.0 abc123\nbar 2.0.0 def456\n" }
    let(:info_foo_content) { "1.0.0 dep1:>= 0|checksum:abc123" }
    let(:info_bar_content) { "2.0.0 |checksum:def456" }

    before do
      # Create the directory structure that Cache expects
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))

      # Write names file
      File.write(File.join(directory, "names"), names_content)

      # Write versions file
      File.write(File.join(directory, "versions"), versions_content)

      # Write info files for gems
      File.write(File.join(directory, "info", "foo"), info_foo_content)
      File.write(File.join(directory, "info", "bar"), info_bar_content)
    end

    let(:client) { described_class.new(directory) }

    describe "#names" do
      it "returns an array of gem names from the names file" do
        result = client.names
        expect(result).to be_a(Array)
        expect(result).to include("foo")
        expect(result).to include("bar")
        expect(result).to include("baz")
      end

      it "does not include the header separator" do
        result = client.names
        expect(result).not_to include("---")
      end
    end

    describe "#versions" do
      it "returns a hash of gem versions keyed by name" do
        result = client.versions
        expect(result).to be_a(Hash)
        expect(result.keys).to include("foo")
        expect(result.keys).to include("bar")
      end

      it "contains version arrays for each gem name" do
        result = client.versions
        expect(result["foo"]).to be_a(Array)
        expect(result["foo"]).not_to be_empty
        expect(result["bar"]).to be_a(Array)
        expect(result["bar"]).not_to be_empty
      end
    end

    describe "#info" do
      it "returns an array of info arrays for a given gem" do
        result = client.info("foo")
        expect(result).to be_a(Array)
        expect(result).not_to be_empty
      end

      it "includes the gem name at INFO_NAME index" do
        result = client.info("foo")
        first_entry = result.first
        expect(first_entry).not_to be_nil
        expect(first_entry[described_class::INFO_NAME]).to eq("foo")
      end

      it "includes the version at INFO_VERSION index" do
        result = client.info("foo")
        first_entry = result.first
        expect(first_entry[described_class::INFO_VERSION]).to eq("1.0.0")
      end
    end

    describe "#dependencies" do
      it "returns an array of info arrays for each requested name" do
        result = client.dependencies(["foo", "bar"])
        expect(result).to be_a(Array)
        expect(result.length).to eq(2)
      end

      it "maps each name to its info result" do
        result = client.dependencies(["foo"])
        expect(result.length).to eq(1)
        # Each element is the info array for that gem
        expect(result.first).to be_a(Array)
      end

      it "returns an empty array for an empty names list" do
        result = client.dependencies([])
        expect(result).to be_a(Array)
        expect(result).to be_empty
      end
    end

    describe "#latest_version" do
      it "returns a Gem::Version object" do
        result = client.latest_version("foo")
        expect(result).to be_a(Gem::Version)
      end

      it "returns the highest version for a gem" do
        result = client.latest_version("foo")
        expect(result).to eq(Gem::Version.new("1.0.0"))
      end
    end

    describe "#available?" do
      context "when versions data exists" do
        it "returns true" do
          # Trigger versions parsing first
          client.versions
          expect(client.available?).to be true
        end
      end
    end

    describe "#reset!" do
      it "can be called without raising an error" do
        expect { client.reset! }.not_to raise_error
      end

      it "allows fetching again after reset" do
        # First fetch
        client.names
        # Reset
        client.reset!
        # Fetch again - should not raise
        result = client.names
        expect(result).to be_a(Array)
      end
    end
  end

  describe "with empty directory" do
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
      end
    end

    describe "#dependencies" do
      it "returns empty arrays for each name when no info files exist" do
        result = client.dependencies(["nonexistent"])
        expect(result).to be_a(Array)
        expect(result.length).to eq(1)
        expect(result.first).to be_a(Array)
        expect(result.first).to be_empty
      end
    end
  end

  describe "with multiple versions of same gem" do
    let(:client) { described_class.new(directory) }

    before do
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))

      # versions file with multiple versions for a single gem
      File.write(File.join(directory, "versions"), "---\nmygem 1.0.0,2.0.0,3.0.0 checksum123\n")

      # info file with multiple versions
      info_content = "1.0.0 |checksum:abc\n2.0.0 dep1:>= 1.0|checksum:def\n3.0.0 dep1:>= 1.0,dep2:~> 2.0|checksum:ghi"
      File.write(File.join(directory, "info", "mygem"), info_content)
    end

    describe "#versions" do
      it "contains multiple version entries for the gem" do
        result = client.versions
        expect(result["mygem"]).to be_a(Array)
        expect(result["mygem"].length).to eq(3)
      end
    end

    describe "#info" do
      it "returns all version entries for the gem" do
        result = client.info("mygem")
        expect(result.length).to eq(3)
      end

      it "includes version 1.0.0" do
        result = client.info("mygem")
        versions = result.map { |entry| entry[described_class::INFO_VERSION] }
        expect(versions).to include("1.0.0")
      end

      it "includes version 2.0.0" do
        result = client.info("mygem")
        versions = result.map { |entry| entry[described_class::INFO_VERSION] }
        expect(versions).to include("2.0.0")
      end

      it "includes version 3.0.0" do
        result = client.info("mygem")
        versions = result.map { |entry| entry[described_class::INFO_VERSION] }
        expect(versions).to include("3.0.0")
      end
    end

    describe "#latest_version" do
      it "returns the highest version" do
        result = client.latest_version("mygem")
        expect(result).to eq(Gem::Version.new("3.0.0"))
      end
    end
  end

  describe "with version deletion markers" do
    let(:client) { described_class.new(directory) }

    before do
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))

      # versions with deletion marker (-) for yanked versions
      versions_data = "---\nmygem 1.0.0,2.0.0,-1.0.0 checksum123\n"
      File.write(File.join(directory, "versions"), versions_data)

      File.write(File.join(directory, "info", "mygem"), "2.0.0 |checksum:def")
    end

    describe "#versions" do
      it "removes yanked versions from the list" do
        result = client.versions
        versions = result["mygem"].map { |v| v[1] }
        expect(versions).to include("2.0.0")
        expect(versions).not_to include("1.0.0")
      end
    end
  end

  describe "with platform-specific versions" do
    let(:client) { described_class.new(directory) }

    before do
      FileUtils.mkdir_p(File.join(directory, "info"))
      FileUtils.mkdir_p(File.join(directory, "info-special-characters"))
      FileUtils.mkdir_p(File.join(directory, "info-etags"))

      File.write(File.join(directory, "versions"), "---\nmygem 1.0.0-java checksum123\n")
      File.write(File.join(directory, "info", "mygem"), "1.0.0-java |checksum:abc")
    end

    describe "#versions" do
      it "includes platform-specific version entries" do
        result = client.versions
        expect(result["mygem"]).to be_a(Array)
        expect(result["mygem"]).not_to be_empty
      end
    end
  end

  describe "nested classes availability" do
    it "has Cache class defined" do
      expect(described_class::Cache).to be_a(Class)
    end

    it "has CacheFile class defined" do
      expect(described_class::CacheFile).to be_a(Class)
    end

    it "has Parser class defined" do
      expect(described_class::Parser).to be_a(Class)
    end

    it "has Updater class defined" do
      expect(described_class::Updater).to be_a(Class)
    end
  end

  describe "thread safety" do
    it "has a DEBUG_MUTEX for synchronizing debug output" do
      mutex = described_class::DEBUG_MUTEX
      expect(mutex).to respond_to(:synchronize)
    end

    it "DEBUG_MUTEX can be used for synchronization" do
      result = described_class::DEBUG_MUTEX.synchronize { 42 }
      expect(result).to eq(42)
    end
  end
end
