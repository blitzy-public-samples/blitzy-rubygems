# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "bundler/checksum"

RSpec.describe Bundler::Checksum do
  # Precomputed SHA256 hex digest of "hello world"
  let(:hello_world_hex) { "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9" }
  # Known 64-character hex strings for deterministic testing
  let(:sample_hex_64) { "a" * 64 }
  let(:alt_hex_64) { "b" * 64 }

  describe "::ALGO_SEPARATOR" do
    it "is the equals sign character used to join algo and digest" do
      expect(Bundler::Checksum::ALGO_SEPARATOR).to eq("=")
      expect(Bundler::Checksum::ALGO_SEPARATOR).to be_a(String)
    end
  end

  describe ".from_gem" do
    it "returns a Checksum instance with sha256 algo for a given IO" do
      io = StringIO.new("hello world")
      checksum = described_class.from_gem(io, "/tmp/test.gem")
      expect(checksum).to be_a(described_class)
      expect(checksum.algo).to eq("sha256")
    end

    it "computes the correct hex digest from IO content" do
      io = StringIO.new("hello world")
      checksum = described_class.from_gem(io, "/tmp/test.gem")
      expect(checksum.digest).to eq(hello_world_hex)
      expect(checksum.digest.length).to eq(64)
    end

    it "creates a Source with :gem type and the given pathname" do
      io = StringIO.new("hello world")
      checksum = described_class.from_gem(io, "/tmp/test.gem")
      expect(checksum.sources.length).to eq(1)
      expect(checksum.sources.first.type).to eq(:gem)
      expect(checksum.sources.first.location).to eq("/tmp/test.gem")
    end

    it "computes different digests for different content" do
      io1 = StringIO.new("content one")
      io2 = StringIO.new("content two")
      cs1 = described_class.from_gem(io1, "/tmp/a.gem")
      cs2 = described_class.from_gem(io2, "/tmp/b.gem")
      expect(cs1.digest).not_to eq(cs2.digest)
      expect(cs1.algo).to eq(cs2.algo)
    end

    it "computes the known SHA256 digest for empty IO content" do
      io = StringIO.new("")
      checksum = described_class.from_gem(io, "/tmp/empty.gem")
      # SHA256 of empty string is a well-known constant
      expect(checksum.digest).to eq("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
      expect(checksum.algo).to eq("sha256")
    end

    it "handles large content exceeding the internal block size" do
      large_content = "x" * 32_768
      io = StringIO.new(large_content)
      checksum = described_class.from_gem(io, "/tmp/large.gem")
      expect(checksum).to be_a(described_class)
      expect(checksum.digest.length).to eq(64)
    end
  end

  describe ".from_gem_package" do
    context "when checksum validation is not disabled" do
      before do
        allow(Bundler.settings).to receive(:[]).with(:disable_checksum_validation).and_return(nil)
      end

      it "returns nil when gem_package has no @gem instance variable" do
        gem_package = double("gem_package")
        allow(gem_package).to receive(:instance_variable_get).with(:@gem).and_return(nil)
        result = described_class.from_gem_package(gem_package)
        expect(result).to be_nil
        expect(result).not_to be_a(described_class)
      end

      it "returns nil when @gem does not respond to with_read_io" do
        source = double("source")
        allow(source).to receive(:respond_to?).with(:with_read_io).and_return(false)
        gem_package = double("gem_package")
        allow(gem_package).to receive(:instance_variable_get).with(:@gem).and_return(source)
        result = described_class.from_gem_package(gem_package)
        expect(result).to be_nil
        expect(result).not_to be_a(described_class)
      end

      it "computes checksum from the gem IO when source supports with_read_io" do
        io = StringIO.new("test content")
        source = double("source", path: "/tmp/test.gem")
        allow(source).to receive(:respond_to?).with(:with_read_io).and_return(true)
        allow(source).to receive(:with_read_io).and_yield(io)
        gem_package = double("gem_package")
        allow(gem_package).to receive(:instance_variable_get).with(:@gem).and_return(source)
        result = described_class.from_gem_package(gem_package)
        expect(result).to be_a(described_class)
        expect(result.algo).to eq("sha256")
        expect(result.sources.first.type).to eq(:gem)
      end
    end

    context "when checksum validation is disabled" do
      before do
        allow(Bundler.settings).to receive(:[]).with(:disable_checksum_validation).and_return(true)
      end

      it "returns nil without examining the gem package" do
        gem_package = double("gem_package")
        result = described_class.from_gem_package(gem_package)
        expect(result).to be_nil
        expect(result).not_to be_a(described_class)
      end
    end
  end

  describe ".from_api" do
    context "when checksum validation is not disabled" do
      before do
        allow(Bundler.settings).to receive(:[]).with(:disable_checksum_validation).and_return(nil)
      end

      it "returns a Checksum with sha256 algo for a valid hex digest" do
        checksum = described_class.from_api(sample_hex_64, "https://rubygems.org")
        expect(checksum).to be_a(described_class)
        expect(checksum.algo).to eq("sha256")
        expect(checksum.digest).to eq(sample_hex_64)
      end

      it "creates a Source with :api type and the given URI" do
        checksum = described_class.from_api(sample_hex_64, "https://rubygems.org")
        expect(checksum.sources.first.type).to eq(:api)
        expect(checksum.sources.first.location).to eq("https://rubygems.org")
      end

      it "converts a base64 digest to hex format" do
        binary = [hello_world_hex].pack("H*")
        b64 = [binary].pack("m0")
        checksum = described_class.from_api(b64, "https://rubygems.org")
        expect(checksum.digest).to eq(hello_world_hex)
        expect(checksum.algo).to eq("sha256")
      end
    end

    context "when checksum validation is disabled" do
      before do
        allow(Bundler.settings).to receive(:[]).with(:disable_checksum_validation).and_return(true)
      end

      it "returns nil without constructing a Checksum" do
        result = described_class.from_api(sample_hex_64, "https://rubygems.org")
        expect(result).to be_nil
        expect(result).not_to be_a(described_class)
      end
    end
  end

  describe ".from_lock" do
    it "parses a lock checksum string into algo and hex digest" do
      lock_str = "sha256=#{sample_hex_64}"
      checksum = described_class.from_lock(lock_str, "/tmp/Gemfile.lock")
      expect(checksum.algo).to eq("sha256")
      expect(checksum.digest).to eq(sample_hex_64)
    end

    it "creates a Source with :lock type and the lockfile location" do
      lock_str = "sha256=#{sample_hex_64}"
      checksum = described_class.from_lock(lock_str, "/tmp/Gemfile.lock")
      expect(checksum.sources.first.type).to eq(:lock)
      expect(checksum.sources.first.location).to eq("/tmp/Gemfile.lock")
    end

    it "strips leading and trailing whitespace from the lock checksum string" do
      lock_str = "  sha256=#{sample_hex_64}  "
      checksum = described_class.from_lock(lock_str, "/tmp/Gemfile.lock")
      expect(checksum.algo).to eq("sha256")
      expect(checksum.digest).to eq(sample_hex_64)
    end

    it "produces a checksum that round-trips correctly through to_lock" do
      lock_str = "sha256=#{sample_hex_64}"
      checksum = described_class.from_lock(lock_str, "/tmp/lock")
      expect(checksum.to_lock).to eq(lock_str)
      expect(checksum).to be_a(described_class)
    end
  end

  describe ".to_hexdigest" do
    context "with sha256 algo (default)" do
      it "returns a valid 64-character hex digest unchanged" do
        hex = sample_hex_64
        result = described_class.to_hexdigest(hex)
        expect(result).to eq(hex)
        expect(result.length).to eq(64)
      end

      it "converts a standard base64 SHA256 digest to hex" do
        binary = [hello_world_hex].pack("H*")
        b64 = [binary].pack("m0")
        result = described_class.to_hexdigest(b64)
        expect(result).to eq(hello_world_hex)
        expect(result).to match(/\A[0-9a-f]{64}\z/)
      end

      it "converts a URL-safe base64 SHA256 digest to hex" do
        binary = [hello_world_hex].pack("H*")
        b64 = [binary].pack("m0")
        urlsafe = b64.tr("+/", "-_")
        result = described_class.to_hexdigest(urlsafe)
        expect(result).to eq(hello_world_hex)
        expect(result.length).to eq(64)
      end

      it "raises ArgumentError for an invalid digest string" do
        expect { described_class.to_hexdigest("not-valid-at-all-no-way") }.to raise_error(ArgumentError)
        expect { described_class.to_hexdigest("!!!invalid!!!") }.to raise_error(
          ArgumentError, /is not a valid SHA256 hex or base64 digest/
        )
      end

      it "is case-insensitive for hex digests" do
        upper_hex = sample_hex_64.upcase
        result = described_class.to_hexdigest(upper_hex)
        expect(result).to eq(upper_hex)
        expect(result.length).to eq(64)
      end
    end

    context "with non-sha256 algo" do
      it "returns the digest unchanged regardless of its format" do
        result = described_class.to_hexdigest("anything-goes-here", "md5")
        expect(result).to eq("anything-goes-here")
        expect(result).to be_a(String)
      end
    end
  end

  describe "#initialize" do
    it "stores the algo, digest, and wraps source in an array" do
      source = described_class::Source.new(:lock, "/tmp/lock")
      checksum = described_class.new("sha256", sample_hex_64, source)
      expect(checksum.algo).to eq("sha256")
      expect(checksum.digest).to eq(sample_hex_64)
      expect(checksum.sources).to eq([source])
    end
  end

  describe "#match?" do
    it "returns true when algo and digest both match" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      expect(cs1.match?(cs2)).to be true
      expect(cs2.match?(cs1)).to be true
    end

    it "returns false when digests differ" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{alt_hex_64}", "/tmp/b")
      expect(cs1.match?(cs2)).to be false
      expect(cs2.match?(cs1)).to be false
    end

    it "returns false for a non-Checksum object" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      expect(cs.match?("not a checksum")).to be false
      expect(cs.match?(nil)).to be false
    end
  end

  describe "#==" do
    it "returns true when algo, digest, and sources all match" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      expect(cs1 == cs2).to be true
      expect(cs2 == cs1).to be true
    end

    it "returns false when digests match but sources differ" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      expect(cs1 == cs2).to be false
      expect(cs1.match?(cs2)).to be true
    end

    it "returns false when digests differ" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{alt_hex_64}", "/tmp/a")
      expect(cs1 == cs2).to be false
      expect(cs2 == cs1).to be false
    end
  end

  describe "#eql?" do
    it "behaves identically to == as an alias" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      expect(cs1.eql?(cs2)).to eq(cs1 == cs2)
      expect(cs1.eql?(cs2)).to be true
    end
  end

  describe "#same_source?" do
    it "returns true when other's first source is included in own sources" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      expect(cs1.same_source?(cs2)).to be true
      expect(cs2.same_source?(cs1)).to be true
    end

    it "returns false when other's first source is not in own sources" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      expect(cs1.same_source?(cs2)).to be false
      expect(cs2.same_source?(cs1)).to be false
    end
  end

  describe "#hash" do
    it "returns the same hash for checksums with the same digest" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      expect(cs1.hash).to eq(cs2.hash)
      expect(cs1.hash).to be_a(Integer)
    end

    it "returns different hash values for different digests" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{alt_hex_64}", "/tmp/a")
      expect(cs1.hash).not_to eq(cs2.hash)
      expect(cs1.hash).to be_a(Integer)
    end
  end

  describe "#to_s" do
    it "includes the lock representation and source description" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/Gemfile.lock")
      result = cs.to_s
      expect(result).to include("sha256=#{sample_hex_64}")
      expect(result).to include("from the lockfile CHECKSUMS at /tmp/Gemfile.lock")
    end

    it "indicates multiple sources with an ellipsis when merged" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      cs1.merge!(cs2)
      result = cs1.to_s
      expect(result).to include(", ...")
      expect(result).to include("sha256=")
    end
  end

  describe "#to_lock" do
    it "returns the algo=digest string format used in lockfiles" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
      result = cs.to_lock
      expect(result).to eq("sha256=#{sample_hex_64}")
      expect(result).to include(Bundler::Checksum::ALGO_SEPARATOR)
    end
  end

  describe "#merge!" do
    it "merges sources from a matching checksum and returns self" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      result = cs1.merge!(cs2)
      expect(result).to equal(cs1)
      expect(cs1.sources.length).to eq(2)
    end

    it "does not duplicate the exact same source object on merge" do
      source = described_class::Source.new(:lock, "/tmp/a")
      cs1 = described_class.new("sha256", sample_hex_64, source)
      cs2 = described_class.new("sha256", sample_hex_64, source)
      cs1.merge!(cs2)
      expect(cs1.sources.length).to eq(1)
      expect(cs1.sources.first).to equal(source)
    end

    it "returns nil when digests do not match" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{alt_hex_64}", "/tmp/b")
      result = cs1.merge!(cs2)
      expect(result).to be_nil
      expect(cs1.sources.length).to eq(1)
    end
  end

  describe "#formatted_sources" do
    it "returns a newline-terminated string with the source description" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
      result = cs.formatted_sources
      expect(result).to include("the lockfile CHECKSUMS at /tmp/lock")
      expect(result).to end_with("\n")
    end

    it "joins multiple sources with 'and' separator" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      cs1.merge!(cs2)
      result = cs1.formatted_sources
      expect(result).to include("and")
      expect(result).to end_with("\n")
    end
  end

  describe "#removable?" do
    it "returns true when all sources are of removable types (:lock or :gem)" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
      expect(cs.removable?).to be true
      expect(cs.sources.first.type).to eq(:lock)
    end

    it "returns false when any source is a non-removable type (:api)" do
      source = described_class::Source.new(:api, "https://rubygems.org")
      cs = described_class.new("sha256", sample_hex_64, source)
      expect(cs.removable?).to be false
      expect(cs.sources.first.type).to eq(:api)
    end
  end

  describe "#removal_instructions" do
    it "lists numbered removal steps for each source plus a final bundle install step" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/Gemfile.lock")
      instructions = cs.removal_instructions
      expect(instructions).to include("1.")
      expect(instructions).to include("bundle install")
    end

    it "increments step numbers for multiple sources" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      cs1.merge!(cs2)
      instructions = cs1.removal_instructions
      expect(instructions).to include("1.")
      expect(instructions).to include("2.")
      expect(instructions).to include("3.")
    end
  end

  describe "#inspect" do
    it "returns a concise representation with abbreviated digest and source" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
      result = cs.inspect
      expect(result).to include("Bundler::Checksum")
      expect(result).to include("sha256=#{sample_hex_64[0, 8]}")
      expect(result).to include("from")
    end
  end

  # ---------- Bundler::Checksum::Source ----------

  describe Bundler::Checksum::Source do
    describe "#initialize" do
      it "stores the type and location attributes" do
        source = described_class.new(:lock, "/tmp/Gemfile.lock")
        expect(source.type).to eq(:lock)
        expect(source.location).to eq("/tmp/Gemfile.lock")
      end
    end

    describe "#removable?" do
      it "returns true for :lock type sources" do
        source = described_class.new(:lock, "/tmp/lock")
        expect(source.removable?).to be true
        expect(source.type).to eq(:lock)
      end

      it "returns true for :gem type sources" do
        source = described_class.new(:gem, "/tmp/gem")
        expect(source.removable?).to be true
        expect(source.type).to eq(:gem)
      end

      it "returns false for :api type sources" do
        source = described_class.new(:api, "https://rubygems.org")
        expect(source.removable?).to be false
        expect(source.type).to eq(:api)
      end

      it "returns false for unknown source types" do
        source = described_class.new(:custom, "/tmp/custom")
        expect(source.removable?).to be false
        expect(source.type).to eq(:custom)
      end
    end

    describe "#==" do
      it "returns true for sources with identical type and location" do
        s1 = described_class.new(:lock, "/tmp/a")
        s2 = described_class.new(:lock, "/tmp/a")
        expect(s1 == s2).to be true
        expect(s2 == s1).to be true
      end

      it "returns false for sources with different locations" do
        s1 = described_class.new(:lock, "/tmp/a")
        s2 = described_class.new(:lock, "/tmp/b")
        expect(s1 == s2).to be false
        expect(s2 == s1).to be false
      end

      it "returns false for sources with different types" do
        s1 = described_class.new(:lock, "/tmp/a")
        s2 = described_class.new(:gem, "/tmp/a")
        expect(s1 == s2).to be false
        expect(s2 == s1).to be false
      end

      it "returns false when compared to a non-Source object" do
        source = described_class.new(:lock, "/tmp/a")
        expect(source == "string").to be false
        expect(source == nil).to be false
      end
    end

    describe "#to_s" do
      it "formats :lock source with lockfile CHECKSUMS location" do
        source = described_class.new(:lock, "/tmp/Gemfile.lock")
        expect(source.to_s).to eq("the lockfile CHECKSUMS at /tmp/Gemfile.lock")
        expect(source.to_s).to include("lockfile")
      end

      it "formats :gem source with gem path" do
        source = described_class.new(:gem, "/tmp/my.gem")
        expect(source.to_s).to eq("the gem at /tmp/my.gem")
        expect(source.to_s).to include("gem")
      end

      it "formats :api source with API URI" do
        source = described_class.new(:api, "https://rubygems.org")
        expect(source.to_s).to eq("the API at https://rubygems.org")
        expect(source.to_s).to include("API")
      end

      it "formats unknown type with location and type in parentheses" do
        source = described_class.new(:custom, "/tmp/custom")
        expect(source.to_s).to eq("/tmp/custom (custom)")
        expect(source.to_s).to include("custom")
      end
    end

    describe "#removal" do
      it "provides removal instruction for :lock type" do
        source = described_class.new(:lock, "/tmp/Gemfile.lock")
        expect(source.removal).to eq("remove the matching checksum in /tmp/Gemfile.lock")
        expect(source.removal).to include("remove")
      end

      it "provides removal instruction for :gem type" do
        source = described_class.new(:gem, "/tmp/my.gem")
        expect(source.removal).to eq("remove the gem at /tmp/my.gem")
        expect(source.removal).to include("gem")
      end

      it "provides advisory instruction for :api type" do
        source = described_class.new(:api, "https://rubygems.org")
        expect(source.removal).to include("cannot be locally modified")
        expect(source.removal).to include("update your sources")
      end

      it "provides generic removal instruction for unknown types" do
        source = described_class.new(:custom, "/tmp/custom")
        expect(source.removal).to eq("remove /tmp/custom (custom)")
        expect(source.removal).to include("remove")
      end
    end
  end

  # ---------- Bundler::Checksum::Store ----------

  describe Bundler::Checksum::Store do
    let(:store) { described_class.new }
    let(:spec) { double("spec", lock_name: "rake-13.0.0") }
    let(:alt_spec) { double("spec", lock_name: "rspec-3.0.0") }

    describe "#initialize" do
      it "creates an empty store with size zero" do
        result = store.inspect
        expect(result).to include("size=0")
        expect(result).to include("Bundler::Checksum::Store")
      end
    end

    describe "#inspect" do
      it "includes the class name and current store size" do
        result = store.inspect
        expect(result).to include("Bundler::Checksum::Store")
        expect(result).to include("size=0")
      end

      it "reflects updated size after registering checksums" do
        cs = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        store.register(spec, cs)
        result = store.inspect
        expect(result).to include("size=1")
        expect(result).to include("Bundler::Checksum::Store")
      end
    end

    describe "#register" do
      it "registers a checksum for a spec and marks it as not missing" do
        cs = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        store.register(spec, cs)
        expect(store.missing?(spec)).to be false
        expect(store.to_lock(spec)).to include("sha256=#{sample_hex_64}")
      end

      it "merges sources when registering a matching checksum for the same spec" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
        store.register(spec, cs1)
        store.register(spec, cs2)
        lock_output = store.to_lock(spec)
        expect(lock_output).to include("sha256=#{sample_hex_64}")
        expect(store.missing?(spec)).to be false
      end

      it "raises ChecksumMismatchError when registering a conflicting checksum" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{alt_hex_64}", "/tmp/b")
        store.register(spec, cs1)
        expect { store.register(spec, cs2) }.to raise_error(Bundler::ChecksumMismatchError)
        expect(store.to_lock(spec)).to include(sample_hex_64)
      end

      it "initializes an entry with empty checksums when registering nil" do
        store.register(spec, nil)
        expect(store.missing?(spec)).to be false
        expect(store.to_lock(spec)).to eq("rake-13.0.0")
      end

      it "registers checksums for different specs independently" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        cs2 = Bundler::Checksum.from_lock("sha256=#{alt_hex_64}", "/tmp/lock")
        store.register(spec, cs1)
        store.register(alt_spec, cs2)
        expect(store.to_lock(spec)).to include(sample_hex_64)
        expect(store.to_lock(alt_spec)).to include(alt_hex_64)
      end
    end

    describe "#replace" do
      it "replaces when the new checksum is from the same source" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock1")
        cs2 = Bundler::Checksum.from_lock("sha256=#{alt_hex_64}", "/tmp/lock1")
        store.replace(spec, cs1)
        store.replace(spec, cs2)
        expect(store.to_lock(spec)).to include("sha256=#{alt_hex_64}")
        expect(store.to_lock(spec)).not_to include(sample_hex_64)
      end

      it "merges when the new checksum is from a different source with matching digest" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
        store.replace(spec, cs1)
        store.replace(spec, cs2)
        expect(store.to_lock(spec)).to include("sha256=#{sample_hex_64}")
        expect(store.missing?(spec)).to be false
      end

      it "raises ChecksumMismatchError when different source has different digest" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{alt_hex_64}", "/tmp/b")
        store.replace(spec, cs1)
        expect { store.replace(spec, cs2) }.to raise_error(Bundler::ChecksumMismatchError)
        expect(store.to_lock(spec)).to include(sample_hex_64)
      end

      it "does nothing when given nil checksum" do
        store.replace(spec, nil)
        expect(store.missing?(spec)).to be true
        expect(store.to_lock(spec)).to eq("rake-13.0.0")
      end
    end

    describe "#missing?" do
      it "returns true for a spec that has never been registered" do
        expect(store.missing?(spec)).to be true
        expect(store.missing?(alt_spec)).to be true
      end

      it "returns false for a spec that has been registered with a checksum" do
        cs = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        store.register(spec, cs)
        expect(store.missing?(spec)).to be false
        expect(store.missing?(alt_spec)).to be true
      end

      it "returns false for a spec registered with nil checksum" do
        store.register(spec, nil)
        expect(store.missing?(spec)).to be false
        expect(store.to_lock(spec)).to eq("rake-13.0.0")
      end
    end

    describe "#empty?" do
      it "returns false when spec source is not a Bundler::Source::Rubygems" do
        non_rubygems_source = double("path_source")
        allow(non_rubygems_source).to receive(:is_a?).and_return(false)
        spec_with_source = double("spec", lock_name: "rake-13.0.0", source: non_rubygems_source)
        store.register(spec_with_source, nil)
        expect(store.empty?(spec_with_source)).to be false
        expect(store.missing?(spec_with_source)).to be false
      end

      it "returns true when spec is registered with nil checksum and source is Rubygems" do
        rubygems_source = double("rubygems_source")
        allow(rubygems_source).to receive(:is_a?).with(Bundler::Source::Rubygems).and_return(true)
        spec_with_source = double("spec", lock_name: "rake-13.0.0", source: rubygems_source)
        store.register(spec_with_source, nil)
        expect(store.empty?(spec_with_source)).to be true
        expect(store.missing?(spec_with_source)).to be false
      end

      it "returns false when spec has a real checksum registered and source is Rubygems" do
        rubygems_source = double("rubygems_source")
        allow(rubygems_source).to receive(:is_a?).with(Bundler::Source::Rubygems).and_return(true)
        spec_with_source = double("spec", lock_name: "rake-13.0.0", source: rubygems_source)
        cs = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        store.register(spec_with_source, cs)
        expect(store.empty?(spec_with_source)).to be false
        expect(store.missing?(spec_with_source)).to be false
      end
    end

    describe "#to_lock" do
      it "returns lock_name with checksum for a registered spec" do
        cs = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        store.register(spec, cs)
        result = store.to_lock(spec)
        expect(result).to eq("rake-13.0.0 sha256=#{sample_hex_64}")
        expect(result).to include(spec.lock_name)
      end

      it "returns just the lock_name for a spec registered with nil checksum" do
        store.register(spec, nil)
        result = store.to_lock(spec)
        expect(result).to eq("rake-13.0.0")
        expect(result).not_to include("sha256")
      end

      it "returns just the lock_name for an unregistered spec" do
        result = store.to_lock(spec)
        expect(result).to eq("rake-13.0.0")
        expect(result).not_to include("=")
      end
    end

    describe "#merge!" do
      it "merges all checksums from another store into this store" do
        store2 = described_class.new
        cs = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        store2.register(spec, cs)
        store.merge!(store2)
        expect(store.missing?(spec)).to be false
        expect(store.to_lock(spec)).to include("sha256=#{sample_hex_64}")
      end

      it "merges matching checksums from both stores without conflict" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
        store.register(spec, cs1)
        store2 = described_class.new
        store2.register(spec, cs2)
        store.merge!(store2)
        expect(store.to_lock(spec)).to include("sha256=#{sample_hex_64}")
        expect(store.missing?(spec)).to be false
      end

      it "raises ChecksumMismatchError when merging stores with conflicting digests" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{alt_hex_64}", "/tmp/b")
        store.register(spec, cs1)
        store2 = described_class.new
        store2.register(spec, cs2)
        expect { store.merge!(store2) }.to raise_error(Bundler::ChecksumMismatchError)
        expect(store.to_lock(spec)).to include(sample_hex_64)
      end

      it "handles merging an empty store without error" do
        store2 = described_class.new
        store.merge!(store2)
        expect(store.missing?(spec)).to be true
        expect(store.inspect).to include("size=0")
      end

      it "handles merging multiple specs from another store" do
        store2 = described_class.new
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        cs2 = Bundler::Checksum.from_lock("sha256=#{alt_hex_64}", "/tmp/lock")
        store2.register(spec, cs1)
        store2.register(alt_spec, cs2)
        store.merge!(store2)
        expect(store.missing?(spec)).to be false
        expect(store.missing?(alt_spec)).to be false
      end
    end
  end

  # ---------- ChecksumMismatchError integration ----------

  context "when ChecksumMismatchError is raised from mismatched checksums" do
    it "includes both checksums and lock_name in the error message" do
      existing = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/Gemfile.lock")
      conflicting = described_class.from_lock("sha256=#{alt_hex_64}", "/tmp/other.lock")
      error = Bundler::ChecksumMismatchError.new("rake-13.0.0", existing, conflicting)
      message = error.message
      expect(message).to include("rake-13.0.0")
      expect(message).to include("Bundler found mismatched checksums")
      expect(message).to include("sha256=#{sample_hex_64}")
      expect(message).to include("sha256=#{alt_hex_64}")
    end

    it "provides mismatch resolution instructions with removal steps" do
      existing = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/Gemfile.lock")
      conflicting = described_class.from_lock("sha256=#{alt_hex_64}", "/tmp/other.lock")
      error = Bundler::ChecksumMismatchError.new("rake-13.0.0", existing, conflicting)
      instructions = error.mismatch_resolution_instructions
      expect(instructions).to include("resolve")
      expect(instructions).to be_a(String)
    end

    it "includes the disable_checksum_validation hint in the message" do
      existing = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/Gemfile.lock")
      conflicting = described_class.from_lock("sha256=#{alt_hex_64}", "/tmp/other.lock")
      error = Bundler::ChecksumMismatchError.new("rake-13.0.0", existing, conflicting)
      message = error.message
      expect(message).to include("disable_checksum_validation")
      expect(message).to include("bundle config")
    end

    it "handles mixed removable and non-removable sources in resolution instructions" do
      existing = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/Gemfile.lock")
      api_source = described_class::Source.new(:api, "https://rubygems.org")
      conflicting = described_class.new("sha256", alt_hex_64, api_source)
      error = Bundler::ChecksumMismatchError.new("rake-13.0.0", existing, conflicting)
      instructions = error.mismatch_resolution_instructions
      expect(instructions).to include("trust")
      expect(instructions).to be_a(String)
    end
  end
end
