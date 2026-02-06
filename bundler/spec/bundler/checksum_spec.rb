# frozen_string_literal: true

require "stringio"
require "bundler/checksum"

RSpec.describe Bundler::Checksum do
  # Precomputed SHA256 hex digest of "hello world"
  let(:hello_world_hex) { "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9" }
  let(:sample_hex_64) { "a" * 64 }
  let(:alt_hex_64) { "b" * 64 }

  describe "::ALGO_SEPARATOR" do
    it "is the equals sign character" do
      expect(Bundler::Checksum::ALGO_SEPARATOR).to eq("=")
    end
  end

  describe ".from_gem" do
    it "returns a Checksum with sha256 algo for a given IO" do
      io = StringIO.new("hello world")
      checksum = described_class.from_gem(io, "/tmp/test.gem")
      expect(checksum).to be_a(described_class)
      expect(checksum.algo).to eq("sha256")
    end

    it "computes the correct hex digest from IO content" do
      io = StringIO.new("hello world")
      checksum = described_class.from_gem(io, "/tmp/test.gem")
      expect(checksum.digest).to eq(hello_world_hex)
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
    end

    it "computes correct digest for empty IO content" do
      io = StringIO.new("")
      checksum = described_class.from_gem(io, "/tmp/empty.gem")
      # SHA256 of empty string
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

  describe ".from_api" do
    context "when checksum validation is not disabled" do
      before do
        allow(Bundler.settings).to receive(:[]).with(:disable_checksum_validation).and_return(nil)
      end

      it "returns a Checksum for a valid hex digest" do
        checksum = described_class.from_api(sample_hex_64, "https://rubygems.org")
        expect(checksum).to be_a(described_class)
        expect(checksum.algo).to eq("sha256")
        expect(checksum.digest).to eq(sample_hex_64)
      end

      it "creates a Source with :api type" do
        checksum = described_class.from_api(sample_hex_64, "https://rubygems.org")
        expect(checksum.sources.first.type).to eq(:api)
        expect(checksum.sources.first.location).to eq("https://rubygems.org")
      end

      it "converts base64 digest to hex" do
        # Base64 encode the binary form of the hello_world SHA256
        binary = [hello_world_hex].pack("H*")
        b64 = [binary].pack("m0")
        checksum = described_class.from_api(b64, "https://rubygems.org")
        expect(checksum.digest).to eq(hello_world_hex)
      end
    end

    context "when checksum validation is disabled" do
      before do
        allow(Bundler.settings).to receive(:[]).with(:disable_checksum_validation).and_return(true)
      end

      it "returns nil" do
        result = described_class.from_api(sample_hex_64, "https://rubygems.org")
        expect(result).to be_nil
      end
    end
  end

  describe ".from_lock" do
    it "parses a lock checksum string into algo and digest" do
      lock_str = "sha256=#{sample_hex_64}"
      checksum = described_class.from_lock(lock_str, "/tmp/Gemfile.lock")
      expect(checksum.algo).to eq("sha256")
      expect(checksum.digest).to eq(sample_hex_64)
    end

    it "creates a Source with :lock type" do
      lock_str = "sha256=#{sample_hex_64}"
      checksum = described_class.from_lock(lock_str, "/tmp/Gemfile.lock")
      expect(checksum.sources.first.type).to eq(:lock)
      expect(checksum.sources.first.location).to eq("/tmp/Gemfile.lock")
    end

    it "strips whitespace from the lock checksum string" do
      lock_str = "  sha256=#{sample_hex_64}  "
      checksum = described_class.from_lock(lock_str, "/tmp/Gemfile.lock")
      expect(checksum.algo).to eq("sha256")
      expect(checksum.digest).to eq(sample_hex_64)
    end

    it "handles lock checksum with only algo separator once" do
      lock_str = "sha256=#{sample_hex_64}"
      checksum = described_class.from_lock(lock_str, "/tmp/lock")
      expect(checksum.to_lock).to eq(lock_str)
    end
  end

  describe ".to_hexdigest" do
    context "with sha256 algo (default)" do
      it "returns a valid hex digest unchanged" do
        hex = sample_hex_64
        expect(described_class.to_hexdigest(hex)).to eq(hex)
      end

      it "converts a standard base64 SHA256 digest to hex" do
        binary = [hello_world_hex].pack("H*")
        b64 = [binary].pack("m0")
        result = described_class.to_hexdigest(b64)
        expect(result).to eq(hello_world_hex)
      end

      it "converts a URL-safe base64 SHA256 digest to hex" do
        binary = [hello_world_hex].pack("H*")
        b64 = [binary].pack("m0")
        urlsafe = b64.tr("+/", "-_")
        result = described_class.to_hexdigest(urlsafe)
        expect(result).to eq(hello_world_hex)
      end

      it "raises ArgumentError for an invalid digest string" do
        expect { described_class.to_hexdigest("not-valid-at-all-no-way") }.to raise_error(
          ArgumentError, /is not a valid SHA256 hex or base64 digest/
        )
      end

      it "is case-insensitive for hex digests" do
        upper_hex = sample_hex_64.upcase
        expect(described_class.to_hexdigest(upper_hex)).to eq(upper_hex)
      end
    end

    context "with non-sha256 algo" do
      it "returns the digest unchanged regardless of format" do
        result = described_class.to_hexdigest("anything-goes-here", "md5")
        expect(result).to eq("anything-goes-here")
      end
    end
  end

  describe "#initialize" do
    it "stores the algo, digest, and source" do
      source = described_class::Source.new(:lock, "/tmp/lock")
      checksum = described_class.new("sha256", sample_hex_64, source)
      expect(checksum.algo).to eq("sha256")
      expect(checksum.digest).to eq(sample_hex_64)
      expect(checksum.sources).to eq([source])
    end
  end

  describe "#match?" do
    it "returns true when algo and digest match" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      expect(cs1.match?(cs2)).to be true
    end

    it "returns false when digests differ" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{alt_hex_64}", "/tmp/b")
      expect(cs1.match?(cs2)).to be false
    end

    it "returns false for a non-Checksum object" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      expect(cs.match?("not a checksum")).to be false
    end
  end

  describe "#==" do
    it "returns true when algo, digest, and sources all match" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      expect(cs1 == cs2).to be true
    end

    it "returns false when digests match but sources differ" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      expect(cs1 == cs2).to be false
    end

    it "returns false when digests differ" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{alt_hex_64}", "/tmp/a")
      expect(cs1 == cs2).to be false
    end
  end

  describe "#eql?" do
    it "is aliased to ==" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      expect(cs1.eql?(cs2)).to eq(cs1 == cs2)
    end
  end

  describe "#same_source?" do
    it "returns true when other's first source is included in own sources" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      expect(cs1.same_source?(cs2)).to be true
    end

    it "returns false when other's first source is not in own sources" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      expect(cs1.same_source?(cs2)).to be false
    end
  end

  describe "#hash" do
    it "returns the same hash for checksums with the same digest" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      expect(cs1.hash).to eq(cs2.hash)
    end

    it "returns different hash values for different digests" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{alt_hex_64}", "/tmp/a")
      expect(cs1.hash).not_to eq(cs2.hash)
    end
  end

  describe "#to_s" do
    it "includes the lock representation and source description" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/Gemfile.lock")
      result = cs.to_s
      expect(result).to include("sha256=#{sample_hex_64}")
      expect(result).to include("from the lockfile CHECKSUMS at /tmp/Gemfile.lock")
    end

    it "indicates multiple sources with an ellipsis" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
      cs1.merge!(cs2)
      result = cs1.to_s
      expect(result).to include(", ...")
    end
  end

  describe "#to_lock" do
    it "returns the algo=digest format" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
      expect(cs.to_lock).to eq("sha256=#{sample_hex_64}")
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
    end

    it "retains both sources when merging from separate from_lock calls with same location" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs1.merge!(cs2)
      # Source does not override hash/eql?, so uniq! uses object identity
      expect(cs1.sources.length).to eq(2)
    end

    it "returns nil when digests do not match" do
      cs1 = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
      cs2 = described_class.from_lock("sha256=#{alt_hex_64}", "/tmp/b")
      expect(cs1.merge!(cs2)).to be_nil
    end
  end

  describe "#formatted_sources" do
    it "returns a newline-terminated string with source descriptions" do
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
    end
  end

  describe "#removable?" do
    it "returns true when all sources are removable (lock or gem types)" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
      expect(cs.removable?).to be true
    end

    it "returns false when any source is not removable" do
      source = described_class::Source.new(:api, "https://rubygems.org")
      cs = described_class.new("sha256", sample_hex_64, source)
      expect(cs.removable?).to be false
    end
  end

  describe "#removal_instructions" do
    it "lists numbered removal steps for each source plus a final bundle install step" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/Gemfile.lock")
      instructions = cs.removal_instructions
      expect(instructions).to include("1.")
      expect(instructions).to include("2.")
      expect(instructions).to include("bundle install")
    end
  end

  describe "#inspect" do
    it "returns a concise representation with abbreviated digest" do
      cs = described_class.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
      result = cs.inspect
      expect(result).to include("Bundler::Checksum")
      expect(result).to include("sha256=#{sample_hex_64[0, 8]}")
      expect(result).to include("from")
    end
  end

  describe Bundler::Checksum::Source do
    describe "#initialize" do
      it "stores type and location" do
        source = described_class.new(:lock, "/tmp/Gemfile.lock")
        expect(source.type).to eq(:lock)
        expect(source.location).to eq("/tmp/Gemfile.lock")
      end
    end

    describe "#removable?" do
      it "returns true for :lock type" do
        source = described_class.new(:lock, "/tmp/lock")
        expect(source.removable?).to be true
      end

      it "returns true for :gem type" do
        source = described_class.new(:gem, "/tmp/gem")
        expect(source.removable?).to be true
      end

      it "returns false for :api type" do
        source = described_class.new(:api, "https://rubygems.org")
        expect(source.removable?).to be false
      end

      it "returns false for unknown types" do
        source = described_class.new(:custom, "/tmp/custom")
        expect(source.removable?).to be false
      end
    end

    describe "#==" do
      it "returns true for sources with same type and location" do
        s1 = described_class.new(:lock, "/tmp/a")
        s2 = described_class.new(:lock, "/tmp/a")
        expect(s1 == s2).to be true
      end

      it "returns false for sources with different locations" do
        s1 = described_class.new(:lock, "/tmp/a")
        s2 = described_class.new(:lock, "/tmp/b")
        expect(s1 == s2).to be false
      end

      it "returns false for sources with different types" do
        s1 = described_class.new(:lock, "/tmp/a")
        s2 = described_class.new(:gem, "/tmp/a")
        expect(s1 == s2).to be false
      end

      it "returns false when compared to a non-Source object" do
        source = described_class.new(:lock, "/tmp/a")
        expect(source == "string").to be false
      end
    end

    describe "#to_s" do
      it "formats :lock source with lockfile location" do
        source = described_class.new(:lock, "/tmp/Gemfile.lock")
        expect(source.to_s).to eq("the lockfile CHECKSUMS at /tmp/Gemfile.lock")
      end

      it "formats :gem source with gem path" do
        source = described_class.new(:gem, "/tmp/my.gem")
        expect(source.to_s).to eq("the gem at /tmp/my.gem")
      end

      it "formats :api source with API URI" do
        source = described_class.new(:api, "https://rubygems.org")
        expect(source.to_s).to eq("the API at https://rubygems.org")
      end

      it "formats unknown type with location and type in parentheses" do
        source = described_class.new(:custom, "/tmp/custom")
        expect(source.to_s).to eq("/tmp/custom (custom)")
      end
    end

    describe "#removal" do
      it "provides removal instruction for :lock type" do
        source = described_class.new(:lock, "/tmp/Gemfile.lock")
        expect(source.removal).to eq("remove the matching checksum in /tmp/Gemfile.lock")
      end

      it "provides removal instruction for :gem type" do
        source = described_class.new(:gem, "/tmp/my.gem")
        expect(source.removal).to eq("remove the gem at /tmp/my.gem")
      end

      it "provides removal instruction for :api type" do
        source = described_class.new(:api, "https://rubygems.org")
        expect(source.removal).to include("cannot be locally modified")
      end

      it "provides removal instruction for unknown types" do
        source = described_class.new(:custom, "/tmp/custom")
        expect(source.removal).to eq("remove /tmp/custom (custom)")
      end
    end
  end

  describe Bundler::Checksum::Store do
    let(:store) { described_class.new }
    let(:spec) { double("spec", lock_name: "rake-13.0.0") }
    let(:alt_spec) { double("spec", lock_name: "rspec-3.0.0") }

    describe "#initialize" do
      it "creates an empty store" do
        expect(store.inspect).to include("size=0")
      end
    end

    describe "#inspect" do
      it "includes the class name and store size" do
        result = store.inspect
        expect(result).to include("Bundler::Checksum::Store")
        expect(result).to include("size=0")
      end
    end

    describe "#register" do
      it "registers a checksum for a spec" do
        cs = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        store.register(spec, cs)
        expect(store.missing?(spec)).to be false
      end

      it "merges sources when registering a matching checksum for the same spec" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
        store.register(spec, cs1)
        store.register(spec, cs2)
        lock_output = store.to_lock(spec)
        expect(lock_output).to include("sha256=#{sample_hex_64}")
      end

      it "raises ChecksumMismatchError when registering a mismatched checksum" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{alt_hex_64}", "/tmp/b")
        store.register(spec, cs1)
        expect { store.register(spec, cs2) }.to raise_error(Bundler::ChecksumMismatchError)
      end

      it "initializes an entry when registering nil checksum" do
        store.register(spec, nil)
        expect(store.missing?(spec)).to be false
      end
    end

    describe "#replace" do
      it "replaces when the new checksum is from the same source" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock1")
        cs2 = Bundler::Checksum.from_lock("sha256=#{alt_hex_64}", "/tmp/lock1")
        store.replace(spec, cs1)
        store.replace(spec, cs2)
        expect(store.to_lock(spec)).to include("sha256=#{alt_hex_64}")
      end

      it "merges when the new checksum is from a different source with matching digest" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
        store.replace(spec, cs1)
        store.replace(spec, cs2)
        expect(store.to_lock(spec)).to include("sha256=#{sample_hex_64}")
      end

      it "raises ChecksumMismatchError when different source has different digest" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{alt_hex_64}", "/tmp/b")
        store.replace(spec, cs1)
        expect { store.replace(spec, cs2) }.to raise_error(Bundler::ChecksumMismatchError)
      end

      it "does nothing when given nil checksum" do
        store.replace(spec, nil)
        expect(store.missing?(spec)).to be true
      end
    end

    describe "#missing?" do
      it "returns true for an unregistered spec" do
        expect(store.missing?(spec)).to be true
      end

      it "returns false for a registered spec" do
        cs = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        store.register(spec, cs)
        expect(store.missing?(spec)).to be false
      end
    end

    describe "#to_lock" do
      it "returns lock_name with checksum for a registered spec" do
        cs = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        store.register(spec, cs)
        result = store.to_lock(spec)
        expect(result).to eq("rake-13.0.0 sha256=#{sample_hex_64}")
      end

      it "returns just the lock_name for a spec with nil checksum" do
        store.register(spec, nil)
        result = store.to_lock(spec)
        expect(result).to eq("rake-13.0.0")
      end

      it "returns just the lock_name for an unregistered spec" do
        result = store.to_lock(spec)
        expect(result).to eq("rake-13.0.0")
      end
    end

    describe "#merge!" do
      it "merges checksums from another store" do
        store2 = described_class.new
        cs = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/lock")
        store2.register(spec, cs)
        store.merge!(store2)
        expect(store.missing?(spec)).to be false
        expect(store.to_lock(spec)).to include("sha256=#{sample_hex_64}")
      end

      it "merges matching checksums from both stores" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/b")
        store.register(spec, cs1)
        store2 = described_class.new
        store2.register(spec, cs2)
        store.merge!(store2)
        expect(store.to_lock(spec)).to include("sha256=#{sample_hex_64}")
      end

      it "raises ChecksumMismatchError when merging mismatched checksums" do
        cs1 = Bundler::Checksum.from_lock("sha256=#{sample_hex_64}", "/tmp/a")
        cs2 = Bundler::Checksum.from_lock("sha256=#{alt_hex_64}", "/tmp/b")
        store.register(spec, cs1)
        store2 = described_class.new
        store2.register(spec, cs2)
        expect { store.merge!(store2) }.to raise_error(Bundler::ChecksumMismatchError)
      end
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
      end

      it "returns nil when @gem does not respond to with_read_io" do
        source = double("source")
        allow(source).to receive(:respond_to?).with(:with_read_io).and_return(false)
        gem_package = double("gem_package")
        allow(gem_package).to receive(:instance_variable_get).with(:@gem).and_return(source)
        result = described_class.from_gem_package(gem_package)
        expect(result).to be_nil
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

      it "returns nil" do
        gem_package = double("gem_package")
        result = described_class.from_gem_package(gem_package)
        expect(result).to be_nil
      end
    end
  end
end
