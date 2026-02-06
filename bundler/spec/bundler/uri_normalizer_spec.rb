# frozen_string_literal: true

require "spec_helper"
require "bundler/uri_normalizer"

RSpec.describe Bundler::URINormalizer do
  describe ".normalize_suffix" do
    context "when trailing_slash is true (default)" do
      it "appends a trailing slash to a URI that does not end with one" do
        uri = "https://rubygems.org"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/")
        expect(result).to end_with("/")
      end

      it "leaves a URI unchanged when it already ends with a trailing slash" do
        uri = "https://rubygems.org/"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/")
        expect(result).to eq(uri)
      end

      it "appends trailing slash to a URI with a multi-segment path" do
        uri = "https://rubygems.org/api/v1"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/api/v1/")
        expect(result.length).to eq(uri.length + 1)
      end

      it "preserves a multi-segment path URI that already has a trailing slash" do
        uri = "https://rubygems.org/api/v1/"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/api/v1/")
        expect(result).to eq(uri)
      end

      it "behaves identically when trailing_slash: true is passed explicitly" do
        uri = "https://rubygems.org"
        result_default = described_class.normalize_suffix(uri)
        result_explicit = described_class.normalize_suffix(uri, trailing_slash: true)
        expect(result_default).to eq("https://rubygems.org/")
        expect(result_explicit).to eq(result_default)
      end

      it "handles a URI with port number by appending a trailing slash" do
        uri = "https://gems.example.com:8443/repo"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://gems.example.com:8443/repo/")
        expect(result).to end_with("/")
      end

      it "handles file protocol URIs" do
        uri = "file:///home/user/gems"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("file:///home/user/gems/")
        expect(result).to end_with("/")
      end

      it "handles git+ssh protocol URIs" do
        uri = "git+ssh://git@github.com/user/repo"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("git+ssh://git@github.com/user/repo/")
        expect(result).to start_with("git+ssh://")
      end
    end

    context "when trailing_slash is false" do
      it "removes the trailing slash from a URI that ends with one" do
        uri = "https://rubygems.org/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://rubygems.org")
        expect(result).not_to end_with("/")
      end

      it "leaves a URI unchanged when it does not end with a trailing slash" do
        uri = "https://rubygems.org"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://rubygems.org")
        expect(result).to eq(uri)
      end

      it "removes trailing slash from a multi-segment path URI" do
        uri = "https://rubygems.org/api/v1/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://rubygems.org/api/v1")
        expect(result.length).to eq(uri.length - 1)
      end

      it "preserves a multi-segment path URI without trailing slash" do
        uri = "https://rubygems.org/api/v1"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://rubygems.org/api/v1")
        expect(result).to eq(uri)
      end

      it "handles a URI with port number by removing the trailing slash" do
        uri = "https://gems.example.com:8443/repo/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://gems.example.com:8443/repo")
        expect(result).not_to end_with("/")
      end

      it "handles git protocol URIs with trailing slash" do
        uri = "git://github.com/user/repo/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("git://github.com/user/repo")
        expect(result).to start_with("git://")
      end

      it "handles S3 bucket URIs with trailing slash" do
        uri = "s3://my-bucket/gems/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("s3://my-bucket/gems")
        expect(result).not_to end_with("/")
      end
    end

    context "credential preservation" do
      it "preserves authentication credentials when appending trailing slash" do
        uri = "https://user:password@gems.example.com/private"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://user:password@gems.example.com/private/")
        expect(result).to include("user:password@")
      end

      it "preserves authentication credentials when URI already has trailing slash" do
        uri = "https://user:password@gems.example.com/private/"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://user:password@gems.example.com/private/")
        expect(result).to eq(uri)
      end

      it "preserves authentication credentials when removing trailing slash" do
        uri = "https://user:password@gems.example.com/private/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://user:password@gems.example.com/private")
        expect(result).to include("user:password@")
      end

      it "preserves authentication credentials when URI has no trailing slash" do
        uri = "https://user:password@gems.example.com/private"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://user:password@gems.example.com/private")
        expect(result).to eq(uri)
      end

      it "preserves complex credentials with special characters in username" do
        uri = "https://deploy_token:secret123@registry.example.com/gems"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://deploy_token:secret123@registry.example.com/gems/")
        expect(result).to include("deploy_token:secret123@")
      end
    end

    context "edge cases" do
      it "appends trailing slash to an empty string" do
        uri = ""
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("/")
        expect(result.length).to eq(1)
      end

      it "returns empty string unchanged when trailing_slash is false" do
        uri = ""
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("")
        expect(result).to be_empty
      end

      it "leaves a single slash unchanged when trailing_slash is true" do
        uri = "/"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("/")
        expect(result).to eq(uri)
      end

      it "removes the only slash when trailing_slash is false" do
        uri = "/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("")
        expect(result).to be_empty
      end

      it "handles a URI with query parameters by appending trailing slash" do
        uri = "https://rubygems.org/api?key=value"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/api?key=value/")
        expect(result).to include("key=value")
      end

      it "handles a simple file path without trailing slash" do
        uri = "/path/to/gems"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("/path/to/gems/")
        expect(result).to end_with("/")
      end

      it "handles a simple file path with trailing slash" do
        uri = "/path/to/gems/"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("/path/to/gems/")
        expect(result).to eq(uri)
      end

      it "handles a file path when trailing_slash is false" do
        uri = "/path/to/gems/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("/path/to/gems")
        expect(result).not_to end_with("/")
      end

      it "handles URIs with encoded characters" do
        uri = "https://rubygems.org/api/v1?name=%20test"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://rubygems.org/api/v1?name=%20test/")
        expect(result).to include("%20test")
      end

      it "handles URIs with unicode characters" do
        uri = "https://example.com/gëms"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("https://example.com/gëms/")
        expect(result).to end_with("/")
      end

      it "handles URIs with fragment identifiers" do
        uri = "https://rubygems.org/gems#section/"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("https://rubygems.org/gems#section")
        expect(result).to include("#section")
      end
    end

    context "invalid or unusual URI strings" do
      it "handles a string with only whitespace by appending trailing slash" do
        uri = "   "
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("   /")
        expect(result).to end_with("/")
      end

      it "handles a string with only whitespace when trailing_slash is false" do
        uri = "   "
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("   ")
        expect(result).not_to end_with("/")
      end

      it "handles a bare hostname without scheme" do
        uri = "rubygems.org"
        result = described_class.normalize_suffix(uri)
        expect(result).to eq("rubygems.org/")
        expect(result).to end_with("/")
      end

      it "handles a string containing only slashes" do
        uri = "///"
        result = described_class.normalize_suffix(uri, trailing_slash: false)
        expect(result).to eq("//")
        expect(result.length).to eq(uri.length - 1)
      end
    end

    context "idempotency" do
      it "produces the same result when called twice with trailing_slash true" do
        uri = "https://rubygems.org"
        once = described_class.normalize_suffix(uri)
        twice = described_class.normalize_suffix(once)
        expect(once).to eq(twice)
        expect(twice).to eq("https://rubygems.org/")
      end

      it "produces the same result when called twice with trailing_slash false" do
        uri = "https://rubygems.org/"
        once = described_class.normalize_suffix(uri, trailing_slash: false)
        twice = described_class.normalize_suffix(once, trailing_slash: false)
        expect(once).to eq(twice)
        expect(twice).to eq("https://rubygems.org")
      end
    end

    context "module_function accessibility" do
      it "is callable as a module method and responds to normalize_suffix" do
        expect(described_class).to respond_to(:normalize_suffix)
        expect(described_class.normalize_suffix("https://example.com")).to be_a(String)
      end
    end
  end
end
