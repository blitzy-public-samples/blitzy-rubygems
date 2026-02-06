# frozen_string_literal: true

require_relative "helper"
require "rubygems/s3_uri_signer"

# Unit tests for Gem::S3URISigner exercising AWS SigV4 URI signing.
# All tests invoke production code directly — zero reimplemented business logic.
# Credential providers tested: embedded URI, .gemrc s3_source config, and ENV.
# Time is stubbed to a fixed epoch for deterministic signature verification.
class TestGemS3URISigner < Gem::TestCase
  # Fixed epoch used across the existing S3 test suite for reproducible signatures.
  # Corresponds to 2019-06-24 05:19:41 UTC.
  FIXED_TIME = Time.at(1_561_353_581)

  # Known-good signatures from the existing test suite at FIXED_TIME with
  # access_key=testuser, secret=testpass, bucket=my-bucket, path=/gems/specs.4.8.gz, GET.
  SIGNATURE_DEFAULT_REGION   = "b5cb80c1301f7b1c50c4af54f1f6c034f80b56d32f000a855f0a903dc5a8413c"
  SIGNATURE_US_WEST_2        = "ef07487bfd8e3ca594f8fc29775b70c0a0636f51318f95d4f12b2e6e1fd8c716"
  SIGNATURE_WITH_TOKEN       = "e709338735f9077edf8f6b94b247171c266a9605975e08e4a519a123c3322625"

  def setup
    super
  end

  # ------------------------------------------------------------------ #
  # Initialization
  # ------------------------------------------------------------------ #

  def test_initialize_stores_uri_and_method
    uri = Gem::URI.parse("s3://my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    assert_equal uri, signer.uri
    assert_equal "GET", signer.method
  end

  # ------------------------------------------------------------------ #
  # Signing with embedded credentials (user:password in URI)
  # ------------------------------------------------------------------ #

  def test_sign_with_embedded_credentials_returns_https_signed_url
    uri = Gem::URI.parse("s3://testuser:testpass@my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    Time.stub :now, FIXED_TIME do
      signed_uri = signer.sign

      assert_equal "https", signed_uri.scheme
      assert_equal "my-bucket.s3.us-east-1.amazonaws.com", signed_uri.host
      assert_equal "/gems/specs.4.8.gz", signed_uri.path
    end
  end

  # ------------------------------------------------------------------ #
  # Signing with .gemrc s3_source configuration
  # ------------------------------------------------------------------ #

  def test_sign_with_gemrc_s3_source_config
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass" },
    }
    uri = Gem::URI.parse("s3://my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    Time.stub :now, FIXED_TIME do
      signed_uri = signer.sign
      signed_url = signed_uri.to_s

      assert_equal "https", signed_uri.scheme
      assert_match(/X-Amz-Credential=testuser/, signed_url)
      assert_equal SIGNATURE_DEFAULT_REGION,
                   signed_url[/X-Amz-Signature=(\h+)/, 1]
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  # ------------------------------------------------------------------ #
  # Signing with ENV-based credential provider
  # ------------------------------------------------------------------ #

  def test_sign_with_env_credentials
    ENV["AWS_ACCESS_KEY_ID"] = "testuser"
    ENV["AWS_SECRET_ACCESS_KEY"] = "testpass"
    ENV["AWS_SESSION_TOKEN"] = nil
    Gem.configuration[:s3_source] = {
      "my-bucket" => { provider: "env" },
    }
    uri = Gem::URI.parse("s3://my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    Time.stub :now, FIXED_TIME do
      signed_uri = signer.sign
      signed_url = signed_uri.to_s

      assert_equal "https", signed_uri.scheme
      assert_match(/X-Amz-Credential=testuser/, signed_url)
      assert_equal SIGNATURE_DEFAULT_REGION,
                   signed_url[/X-Amz-Signature=(\h+)/, 1]
    end
  ensure
    ENV.delete("AWS_ACCESS_KEY_ID")
    ENV.delete("AWS_SECRET_ACCESS_KEY")
    ENV.delete("AWS_SESSION_TOKEN")
    Gem.configuration[:s3_source] = nil
  end

  # ------------------------------------------------------------------ #
  # ConfigurationError paths
  # ------------------------------------------------------------------ #

  def test_configuration_error_when_no_s3_source_in_gemrc
    uri = Gem::URI.parse("s3://my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    error = assert_raise Gem::S3URISigner::ConfigurationError do
      signer.sign
    end
    assert_match(/no s3_source key exists in \.gemrc/, error.message)
  end

  def test_configuration_error_when_host_key_missing
    Gem.configuration[:s3_source] = {
      "other-bucket" => { id: "testuser", secret: "testpass" },
    }
    uri = Gem::URI.parse("s3://my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    error = assert_raise Gem::S3URISigner::ConfigurationError do
      signer.sign
    end
    assert_match(/no key for host my-bucket in s3_source in \.gemrc/, error.message)
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_configuration_error_when_id_or_secret_missing
    uri = Gem::URI.parse("s3://my-bucket/gems/specs.4.8.gz")

    # Missing id
    Gem.configuration[:s3_source] = {
      "my-bucket" => { secret: "testpass" },
    }
    signer_no_id = Gem::S3URISigner.new(uri, "GET")

    error_no_id = assert_raise Gem::S3URISigner::ConfigurationError do
      signer_no_id.sign
    end
    assert_match(/s3_source for my-bucket missing id or secret/, error_no_id.message)

    # Missing secret
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser" },
    }
    signer_no_secret = Gem::S3URISigner.new(uri, "GET")

    error_no_secret = assert_raise Gem::S3URISigner::ConfigurationError do
      signer_no_secret.sign
    end
    assert_match(/s3_source for my-bucket missing id or secret/, error_no_secret.message)
  ensure
    Gem.configuration[:s3_source] = nil
  end

  # ------------------------------------------------------------------ #
  # Region handling
  # ------------------------------------------------------------------ #

  def test_default_region_is_us_east_1
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass" },
    }
    uri = Gem::URI.parse("s3://my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    Time.stub :now, FIXED_TIME do
      signed_uri = signer.sign
      signed_url = signed_uri.to_s

      assert_match(/s3\.us-east-1\.amazonaws\.com/, signed_url)
      assert_match(/us-east-1%2Fs3%2Faws4_request/, signed_url)
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  def test_custom_region_used_in_credential_scope
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass", region: "us-west-2" },
    }
    uri = Gem::URI.parse("s3://my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    Time.stub :now, FIXED_TIME do
      signed_uri = signer.sign
      signed_url = signed_uri.to_s

      assert_match(/s3\.us-west-2\.amazonaws\.com/, signed_url)
      assert_match(/us-west-2%2Fs3%2Faws4_request/, signed_url)
      assert_equal SIGNATURE_US_WEST_2,
                   signed_url[/X-Amz-Signature=(\h+)/, 1]
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  # ------------------------------------------------------------------ #
  # Signed URL query parameter assertions
  # ------------------------------------------------------------------ #

  def test_signed_url_contains_aws4_hmac_sha256_algorithm
    uri = Gem::URI.parse("s3://testuser:testpass@my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    Time.stub :now, FIXED_TIME do
      signed_uri = signer.sign
      signed_url = signed_uri.to_s

      assert_match(/X-Amz-Algorithm=AWS4-HMAC-SHA256/, signed_url)
      assert_match(/X-Amz-SignedHeaders=host/, signed_url)
    end
  end

  def test_signed_url_contains_amz_credential_with_access_key
    uri = Gem::URI.parse("s3://testuser:testpass@my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    Time.stub :now, FIXED_TIME do
      signed_uri = signer.sign
      signed_url = signed_uri.to_s

      assert_match(/X-Amz-Credential=testuser%2F20190624%2Fus-east-1%2Fs3%2Faws4_request/, signed_url)
      assert_match(/X-Amz-Date=20190624T051941Z/, signed_url)
    end
  end

  def test_signed_url_contains_amz_signature_parameter
    uri = Gem::URI.parse("s3://testuser:testpass@my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    Time.stub :now, FIXED_TIME do
      signed_uri = signer.sign
      signed_url = signed_uri.to_s

      signature = signed_url[/X-Amz-Signature=(\h+)/, 1]
      assert_equal 64, signature.length
      assert_equal SIGNATURE_DEFAULT_REGION, signature
    end
  end

  # ------------------------------------------------------------------ #
  # Session token handling
  # ------------------------------------------------------------------ #

  def test_session_token_included_in_signed_url_when_present
    Gem.configuration[:s3_source] = {
      "my-bucket" => { id: "testuser", secret: "testpass", security_token: "testtoken" },
    }
    uri = Gem::URI.parse("s3://my-bucket/gems/specs.4.8.gz")
    signer = Gem::S3URISigner.new(uri, "GET")

    Time.stub :now, FIXED_TIME do
      signed_uri = signer.sign
      signed_url = signed_uri.to_s

      assert_match(/X-Amz-Security-Token=testtoken/, signed_url)
      assert_equal SIGNATURE_WITH_TOKEN,
                   signed_url[/X-Amz-Signature=(\h+)/, 1]
    end
  ensure
    Gem.configuration[:s3_source] = nil
  end

  # ------------------------------------------------------------------ #
  # Error class hierarchy
  # ------------------------------------------------------------------ #

  def test_configuration_error_is_subclass_of_gem_exception
    assert_operator Gem::S3URISigner::ConfigurationError, :<, Gem::Exception
    error = Gem::S3URISigner::ConfigurationError.new("test message")
    assert_kind_of Gem::Exception, error
  end

  def test_instance_profile_error_is_subclass_of_gem_exception
    assert_operator Gem::S3URISigner::InstanceProfileError, :<, Gem::Exception
    error = Gem::S3URISigner::InstanceProfileError.new("test message")
    assert_kind_of Gem::Exception, error
  end
end
