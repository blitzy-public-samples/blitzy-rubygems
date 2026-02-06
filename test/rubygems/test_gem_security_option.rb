# frozen_string_literal: true

require_relative "helper"
require "rubygems/security_option"
require "rubygems/command"

# Test class for Gem::SecurityOption module.
# Validates security policy option flag parsing, add_security_option method,
# and policy name resolution by invoking the real SecurityOption module
# through a Gem::Command subclass that includes it.
class TestGemSecurityOption < Gem::TestCase
  # Minimal command subclass that includes SecurityOption for testing.
  # This mirrors how production commands (e.g., UnpackCommand) use the module.
  class SecurityTestCommand < Gem::Command
    include Gem::SecurityOption

    def initialize
      super "sectest", "security option test command"
    end

    def execute
    end
  end

  def setup
    super
    @cmd = SecurityTestCommand.new
  end

  # Verify that calling add_security_option registers the --trust-policy
  # option on the command and the command responds to the method.
  def test_add_security_option
    assert_respond_to @cmd, :add_security_option

    @cmd.add_security_option

    # After calling add_security_option, the command's option groups
    # should contain the -P / --trust-policy option under Install/Update.
    option_groups = @cmd.instance_variable_get(:@option_groups)
    install_update_opts = option_groups[:"Install/Update"]

    assert_kind_of Array, install_update_opts
    trust_policy_args = install_update_opts.find do |args, _handler|
      args.any? {|a| a.is_a?(String) && a.include?("--trust-policy") }
    end
    assert trust_policy_args, "Expected --trust-policy option to be registered"

    # Also verify the parser help text includes the trust-policy option
    parser_text = @cmd.send(:parser).to_s
    assert_match(/--trust-policy/, parser_text)
  end

  # Verify that Gem::SecurityOption is a properly defined module
  # with the expected instance methods available for inclusion.
  def test_security_option_module_defined
    assert_kind_of Module, Gem::SecurityOption

    assert_respond_to Gem::SecurityOption, :instance_methods
    assert_includes Gem::SecurityOption.instance_methods, :add_security_option

    # Verify the module can be detected as an ancestor of our test command
    assert_kind_of Gem::SecurityOption, @cmd
  end

  # When OpenSSL is available, verify that a valid policy name (e.g., "HighSecurity")
  # is correctly parsed and results in a Gem::Security::Policy object being set
  # in the command's options hash.
  def test_security_policy_accept
    pend "openssl is missing" unless Gem::HAVE_OPENSSL

    @cmd.add_security_option
    @cmd.handle_options %w[-P HighSecurity]

    assert_kind_of Gem::Security::Policy, @cmd.options[:security_policy]
    assert_equal Gem::Security::HighSecurity, @cmd.options[:security_policy]
  end

  # When OpenSSL is available, verify that each known policy name parses
  # correctly through the --trust-policy option.
  def test_security_policy_accept_all_valid_policies
    pend "openssl is missing" unless Gem::HAVE_OPENSSL

    Gem::Security::Policies.each_key do |policy_name|
      cmd = SecurityTestCommand.new
      cmd.add_security_option
      cmd.handle_options ["-P", policy_name]

      assert_kind_of Gem::Security::Policy, cmd.options[:security_policy]
      assert_equal Gem::Security::Policies[policy_name], cmd.options[:security_policy]
    end
  end

  # When OpenSSL is available, verify that an invalid policy name
  # raises Gem::OptionParser::InvalidArgument with a message listing
  # the valid policy names.
  def test_security_policy_invalid
    pend "openssl is missing" unless Gem::HAVE_OPENSSL

    @cmd.add_security_option

    error = assert_raise Gem::OptionParser::InvalidArgument do
      @cmd.handle_options %w[-P UnknownSecurity]
    end

    assert_include error.message, "UnknownSecurity"
    assert_include error.message, "HighSecurity"
  end

  # When OpenSSL is NOT available, verify that attempting to parse a
  # policy name raises Gem::OptionParser::InvalidArgument with a
  # message about OpenSSL not being installed.
  #
  # This test is skipped when OpenSSL IS available since we cannot
  # easily undefine Gem::Security::HighSecurity in a running process
  # without affecting other tests.
  def test_security_option_without_openssl
    pend "OpenSSL is available, cannot test missing OpenSSL path" if Gem::HAVE_OPENSSL

    @cmd.add_security_option

    error = assert_raise Gem::OptionParser::InvalidArgument do
      @cmd.handle_options %w[-P HighSecurity]
    end

    assert_include error.message, "OpenSSL not installed"
  end

  # Verify that the --trust-policy option is registered under the
  # "Install/Update" option group, matching the production convention
  # used by install and update commands.
  def test_security_option_registered_in_install_update_group
    @cmd.add_security_option

    option_groups = @cmd.instance_variable_get(:@option_groups)

    assert option_groups.key?(:"Install/Update"),
      "Expected Install/Update option group to exist"
    assert_operator option_groups[:"Install/Update"].size, :>=, 1
  end

  # Verify that the long form --trust-policy flag works identically
  # to the short form -P flag.
  def test_security_policy_long_flag
    pend "openssl is missing" unless Gem::HAVE_OPENSSL

    @cmd.add_security_option
    @cmd.handle_options %w[--trust-policy HighSecurity]

    assert_kind_of Gem::Security::Policy, @cmd.options[:security_policy]
    assert_equal Gem::Security::HighSecurity, @cmd.options[:security_policy]
  end

  # Verify that SecurityTestCommand (which includes SecurityOption)
  # properly inherits the handles? capability for the -P flag.
  def test_security_option_handles_flag
    @cmd.add_security_option

    assert @cmd.handles?(%w[-P HighSecurity]),
      "Expected command to handle -P flag after add_security_option"
  end
end
