# frozen_string_literal: true

require "bundler/uri_normalizer"

RSpec.describe Bundler::URINormalizer do
  describe ".normalize_suffix" do
    context "when trailing_slash is true (default)" do
      it "returns the same URI when it already ends with a trailing slash" do
        uri = "https://rubygems.org/"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/")
      end

      it "appends a trailing slash when the URI does not end with one" do
        uri = "https://rubygems.org"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/")
      end

      it "preserves path components and appends trailing slash" do
        uri = "https://rubygems.org/api/v1"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/api/v1/")
      end

      it "preserves path components when trailing slash already present" do
        uri = "https://rubygems.org/api/v1/"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/api/v1/")
      end

      it "handles URIs with authentication credentials" do
        uri = "https://user:password@gems.example.com/private"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://user:password@gems.example.com/private/")
      end

      it "handles URIs with authentication credentials and trailing slash" do
        uri = "https://user:password@gems.example.com/private/"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://user:password@gems.example.com/private/")
      end

      it "handles URIs with port numbers" do
        uri = "https://gems.example.com:8443/repo"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://gems.example.com:8443/repo/")
      end

      it "handles URIs with query strings" do
        uri = "https://rubygems.org/api?key=value"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/api?key=value/")
      end

      it "handles simple file paths" do
        uri = "/path/to/gems"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("/path/to/gems/")
      end

      it "handles file paths with trailing slash" do
        uri = "/path/to/gems/"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("/path/to/gems/")
      end

      it "appends trailing slash to an empty string" do
        uri = ""
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("/")
      end

      it "returns the same single slash for a root path" do
        uri = "/"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("/")
      end

      it "handles git+ssh protocol URIs" do
        uri = "git+ssh://git@github.com/user/repo"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("git+ssh://git@github.com/user/repo/")
      end

      it "handles file protocol URIs" do
        uri = "file:///home/user/gems"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("file:///home/user/gems/")
      end
    end

    context "when trailing_slash is explicitly set to true" do
      it "behaves the same as the default for URIs without trailing slash" do
        uri = "https://rubygems.org"
        result = described_class.normalize_suffix(uri, trailing_slash: true)
        expect(result).to eq("https://rubygems.org/")
      end

      it "behaves the same as the default for URIs with trailing slash" do
        uri = "https://rubygems.org/"
        result = described_class.normalize_suffix(uri, trailing_slash: true)
        expect(result).to eq("https://rubygems.org/")
      end
    end

    context "when trailing_slash is false" do
      it "removes the trailing slash from a URI that ends with one" do
        uri = "https://rubygems.org/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://rubygems.org")
      end

      it "returns the same URI when it does not end with a trailing slash" do
        uri = "https://rubygems.org"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://rubygems.org")
      end

      it "removes trailing slash from a path with multiple segments" do
        uri = "https://rubygems.org/api/v1/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://rubygems.org/api/v1")
      end

      it "preserves a path without trailing slash" do
        uri = "https://rubygems.org/api/v1"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://rubygems.org/api/v1")
      end

      it "handles URIs with authentication credentials" do
        uri = "https://user:password@gems.example.com/private/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://user:password@gems.example.com/private")
      end

      it "preserves URIs with authentication credentials and no trailing slash" do
        uri = "https://user:password@gems.example.com/private"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://user:password@gems.example.com/private")
      end

      it "handles URIs with port numbers" do
        uri = "https://gems.example.com:8443/repo/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://gems.example.com:8443/repo")
      end

      it "handles simple file paths with trailing slash" do
        uri = "/path/to/gems/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("/path/to/gems")
      end

      it "handles simple file paths without trailing slash" do
        uri = "/path/to/gems"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("/path/to/gems")
      end

      it "removes trailing slash from a root path leaving empty string" do
        uri = "/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("")
      end

      it "returns empty string unchanged" do
        uri = ""
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("")
      end

      it "handles git protocol URIs" do
        uri = "git://github.com/user/repo/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("git://github.com/user/repo")
      end

      it "handles S3 bucket URIs with trailing slash" do
        uri = "s3://my-bucket/gems/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("s3://my-bucket/gems")
      end
    end

    context "with special characters in the URI" do
      it "appends trailing slash to URIs with encoded characters" do
        uri = "https://rubygems.org/api/v1?name=%20test"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/api/v1?name=%20test/")
      end

      it "removes trailing slash from URIs with fragment identifiers" do
        uri = "https://rubygems.org/gems#section/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://rubygems.org/gems#section")
      end

      it "handles URIs with unicode characters" do
        uri = "https://example.com/gëms"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://example.com/gëms/")
      end
    end

    context "with the module_function accessibility" do
      it "is callable as a module method" do
        expect(described_class).to respond_to(:normalize_suffix)
      end

      it "produces consistent results when called as module method" do
        result_with_slash = described_class.normalize_suffix("https://example.com")
        result_without_slash = described_class.normalize_suffix("https://example.com/", trailing_slash: false)
        expect(result_with_slash).to eq("https://example.com/")
        expect(result_without_slash).to eq("https://example.com")
      end
    end

    context "idempotency" do
      it "is idempotent when adding trailing slash" do
        uri = "https://rubygems.org"
        once = described_class.normalize_suffix(uri)
        twice = described_class.normalize_suffix(once)
        expect(once).to eq(twice)
        expect(twice).to eq("https://rubygems.org/")
      end

      it "is idempotent when removing trailing slash" do
        uri = "https://rubygems.org/"
        once = described_class.normalize_suffix(uri, trailing_slash: false)
        twice = described_class.normalize_suffix(once, trailing_slash: false)
        expect(once).to eq(twice)
        expect(twice).to eq("https://rubygems.org")
      end
    end
  end
end
