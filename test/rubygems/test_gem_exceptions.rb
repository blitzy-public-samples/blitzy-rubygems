# frozen_string_literal: true

require_relative "helper"
require "rubygems/exceptions"

# Comprehensive unit tests for the Gem exception class hierarchy defined in
# lib/rubygems/exceptions.rb. Each test method directly invokes production
# constructors and accessors, asserting on their return values without
# reimplementing any business logic.
class TestGemExceptions < Gem::TestCase
  def setup
    super

    # Construct shared resolver fixtures using helpers from Gem::TestCase.
    # These are used by DependencyResolutionError, ImpossibleDependenciesError,
    # and UnsatisfiableDependencyError tests.
    @spec_a = util_spec "a", 2
    @dep_a1 = dep "a", "= 1"
    @dep_a2 = dep "a", "= 2"

    @a1_req = Gem::Resolver::DependencyRequest.new @dep_a1, nil
    @a2_req = Gem::Resolver::DependencyRequest.new @dep_a2, nil

    @activated = Gem::Resolver::ActivationRequest.new @spec_a, @a2_req
  end

  # ------------------------------------------------------------------
  # Gem::Exception
  # ------------------------------------------------------------------

  def test_exception_inherits_from_runtime_error
    error = Gem::Exception.new("test message")

    assert_kind_of RuntimeError, error
    assert_equal "test message", error.message
  end

  # ------------------------------------------------------------------
  # Gem::CommandLineError
  # ------------------------------------------------------------------

  def test_command_line_error_inherits_from_gem_exception
    error = Gem::CommandLineError.new("bad argument")

    assert_kind_of Gem::Exception, error
    assert_equal "bad argument", error.message
  end

  # ------------------------------------------------------------------
  # Gem::UnknownCommandError
  # ------------------------------------------------------------------

  def test_unknown_command_error_stores_unknown_command
    error = Gem::UnknownCommandError.new("xyzzy")

    assert_respond_to error, :unknown_command
    assert_equal "xyzzy", error.unknown_command
  end

  def test_unknown_command_error_formats_message
    error = Gem::UnknownCommandError.new("foobar")

    assert_kind_of Gem::Exception, error
    assert_equal "Unknown command foobar", error.message
  end

  # ------------------------------------------------------------------
  # Gem::DependencyError
  # ------------------------------------------------------------------

  def test_dependency_error_inherits_from_gem_exception
    error = Gem::DependencyError.new("dependency problem")

    assert_kind_of Gem::Exception, error
    assert_equal "dependency problem", error.message
  end

  # ------------------------------------------------------------------
  # Gem::DependencyResolutionError
  # ------------------------------------------------------------------

  def test_dependency_resolution_error_stores_conflict
    conflict = Gem::Resolver::Conflict.new @a1_req, @activated

    error = Gem::DependencyResolutionError.new conflict

    assert_respond_to error, :conflict
    assert_equal conflict, error.conflict
  end

  def test_dependency_resolution_error_conflicting_dependencies
    conflict = Gem::Resolver::Conflict.new @a1_req, @activated

    error = Gem::DependencyResolutionError.new conflict

    deps = error.conflicting_dependencies

    assert_kind_of Array, deps
    assert_equal 2, deps.length
    assert_match(/conflicting dependencies/, error.message)
  end

  # ------------------------------------------------------------------
  # Gem::GemNotInHomeException
  # ------------------------------------------------------------------

  def test_gem_not_in_home_exception_has_spec_accessor
    error = Gem::GemNotInHomeException.new("not in home")
    spec = util_spec "b", 1

    assert_respond_to error, :spec
    assert_respond_to error, :spec=

    error.spec = spec

    assert_equal spec, error.spec
  end

  # ------------------------------------------------------------------
  # Gem::UninstallError
  # ------------------------------------------------------------------

  def test_uninstall_error_has_spec_accessor
    error = Gem::UninstallError.new("uninstall failed")
    spec = util_spec "c", 3

    assert_respond_to error, :spec
    assert_respond_to error, :spec=

    error.spec = spec

    assert_equal spec, error.spec
  end

  # ------------------------------------------------------------------
  # Gem::DocumentError
  # ------------------------------------------------------------------

  def test_document_error_inherits_from_gem_exception
    error = Gem::DocumentError.new("doc error")

    assert_kind_of Gem::Exception, error
    assert_equal "doc error", error.message
  end

  # ------------------------------------------------------------------
  # Gem::EndOfYAMLException
  # ------------------------------------------------------------------

  def test_end_of_yaml_exception_inherits_from_gem_exception
    error = Gem::EndOfYAMLException.new("yaml ended")

    assert_kind_of Gem::Exception, error
    assert_equal "yaml ended", error.message
  end

  # ------------------------------------------------------------------
  # Gem::FilePermissionError
  # ------------------------------------------------------------------

  def test_file_permission_error_stores_directory
    error = Gem::FilePermissionError.new("/usr/local/lib")

    assert_respond_to error, :directory
    assert_equal "/usr/local/lib", error.directory
  end

  def test_file_permission_error_formats_message
    error = Gem::FilePermissionError.new("/opt/gems")

    assert_kind_of Gem::Exception, error
    assert_equal "You don't have write permissions for the /opt/gems directory.", error.message
  end

  # ------------------------------------------------------------------
  # Gem::FormatException
  # ------------------------------------------------------------------

  def test_format_exception_has_file_path_accessor
    error = Gem::FormatException.new("bad format")

    assert_respond_to error, :file_path
    assert_respond_to error, :file_path=

    error.file_path = "/path/to/bad.gem"

    assert_equal "/path/to/bad.gem", error.file_path
  end

  # ------------------------------------------------------------------
  # Gem::GemNotFoundException
  # ------------------------------------------------------------------

  def test_gem_not_found_exception_inherits_from_gem_exception
    error = Gem::GemNotFoundException.new("not found")

    assert_kind_of Gem::Exception, error
    assert_equal "not found", error.message
  end

  # ------------------------------------------------------------------
  # Gem::SpecificGemNotFoundException
  # ------------------------------------------------------------------

  def test_specific_gem_not_found_exception_stores_attributes
    errors = ["error one", "error two"]

    error = Gem::SpecificGemNotFoundException.new("mygem", "1.0", errors)

    assert_equal "mygem", error.name
    assert_equal "1.0", error.version
    assert_equal errors, error.errors
  end

  def test_specific_gem_not_found_exception_formats_message
    error = Gem::SpecificGemNotFoundException.new("mygem", ">= 2.0")

    assert_kind_of Gem::GemNotFoundException, error
    assert_match(/Could not find a valid gem 'mygem'/, error.message)
    assert_match(/>= 2\.0/, error.message)
  end

  # ------------------------------------------------------------------
  # Gem::ImpossibleDependenciesError
  # ------------------------------------------------------------------

  def test_impossible_dependencies_error_stores_request_and_conflicts
    request = dependency_request dep("net-ssh", ">= 2.0"), "rye", "0.9.8"

    net_ssh_dep = dependency_request dep("net-ssh", ">= 2.6.5"), "net-ssh", "2.2.2", request

    conflict = Gem::Resolver::Conflict.new net_ssh_dep, net_ssh_dep.requester

    conflicts = [[net_ssh_dep.requester.spec, conflict]]

    error = Gem::ImpossibleDependenciesError.new request, conflicts

    assert_equal request, error.request
    assert_equal conflicts, error.conflicts
    assert_kind_of Gem::Exception, error
  end

  # ------------------------------------------------------------------
  # Gem::InstallError
  # ------------------------------------------------------------------

  def test_install_error_inherits_from_gem_exception
    error = Gem::InstallError.new("install failed")

    assert_kind_of Gem::Exception, error
    assert_equal "install failed", error.message
  end

  # ------------------------------------------------------------------
  # Gem::RuntimeRequirementNotMetError
  # ------------------------------------------------------------------

  def test_runtime_requirement_not_met_error_suggestion_accessor
    error = Gem::RuntimeRequirementNotMetError.new("requirement not met")

    assert_respond_to error, :suggestion
    assert_respond_to error, :suggestion=

    error.suggestion = "Try upgrading Ruby"

    assert_equal "Try upgrading Ruby", error.suggestion
  end

  def test_runtime_requirement_not_met_error_message_format
    error = Gem::RuntimeRequirementNotMetError.new("requirement not met")
    error.suggestion = "Try upgrading Ruby"

    message = error.message

    assert_match(/Try upgrading Ruby/, message)
    assert_match(/requirement not met/, message)
    assert_kind_of Gem::InstallError, error
  end

  # ------------------------------------------------------------------
  # Gem::InvalidSpecificationException
  # ------------------------------------------------------------------

  def test_invalid_specification_exception_exists
    error = Gem::InvalidSpecificationException.new("invalid spec")

    assert_kind_of Gem::Exception, error
    assert_equal "invalid spec", error.message
  end

  # ------------------------------------------------------------------
  # Gem::OperationNotSupportedError
  # ------------------------------------------------------------------

  def test_operation_not_supported_error_exists
    error = Gem::OperationNotSupportedError.new("not supported")

    assert_kind_of Gem::Exception, error
    assert_equal "not supported", error.message
  end

  # ------------------------------------------------------------------
  # Gem::RemoteError hierarchy
  # ------------------------------------------------------------------

  def test_remote_error_hierarchy
    remote_error = Gem::RemoteError.new("remote failed")

    assert_kind_of Gem::Exception, remote_error
    assert_equal "remote failed", remote_error.message

    # Verify subclasses also descend from Gem::Exception
    cancelled = Gem::RemoteInstallationCancelled.new("cancelled")
    assert_kind_of Gem::Exception, cancelled

    skipped = Gem::RemoteInstallationSkipped.new("skipped")
    assert_kind_of Gem::Exception, skipped

    source_exc = Gem::RemoteSourceException.new("source error")
    assert_kind_of Gem::Exception, source_exc
  end

  # ------------------------------------------------------------------
  # Gem::WebauthnVerificationError
  # ------------------------------------------------------------------

  def test_webauthn_verification_error_formats_message
    error = Gem::WebauthnVerificationError.new("timeout expired")

    assert_kind_of Gem::Exception, error
    assert_equal "Security device verification failed: timeout expired", error.message
  end

  # ------------------------------------------------------------------
  # Gem::SystemExitException
  # ------------------------------------------------------------------

  def test_system_exit_exception_exit_code_alias
    error = Gem::SystemExitException.new(1)

    assert_respond_to error, :exit_code
    assert_equal 1, error.exit_code
    assert_equal error.status, error.exit_code
  end

  def test_system_exit_exception_formatted_message
    error = Gem::SystemExitException.new(42)

    assert_kind_of SystemExit, error
    assert_equal "Exiting RubyGems with exit_code 42", error.message
    assert_equal 42, error.exit_code
  end

  # ------------------------------------------------------------------
  # Gem::UnsatisfiableDependencyError
  # ------------------------------------------------------------------

  def test_unsatisfiable_dependency_error_stores_dependency
    a_dep = dep "a", "~> 1"
    req = Gem::Resolver::DependencyRequest.new a_dep, nil

    error = Gem::UnsatisfiableDependencyError.new req

    assert_respond_to error, :dependency
    assert_equal req, error.dependency
    assert_kind_of Gem::DependencyError, error
  end

  def test_unsatisfiable_dependency_error_name_accessor
    a_dep = dep "somegem", ">= 1.0"
    req = Gem::Resolver::DependencyRequest.new a_dep, nil

    error = Gem::UnsatisfiableDependencyError.new req

    assert_equal "somegem", error.name
    assert_respond_to error, :name
  end

  def test_unsatisfiable_dependency_error_version_accessor
    a_dep = dep "anothergem", "~> 2.0"
    req = Gem::Resolver::DependencyRequest.new a_dep, nil

    error = Gem::UnsatisfiableDependencyError.new req

    assert_equal a_dep.requirement, error.version
    assert_respond_to error, :version
  end

  def test_unsatisfiable_dependency_error_platform_mismatch
    a_dep = dep "platformgem", ">= 1.0"
    req = Gem::Resolver::DependencyRequest.new a_dep, nil

    # Construct platform mismatch entries — objects responding to #platform
    platform_entry = Struct.new(:platform).new(Gem::Platform.new("java"))

    error = Gem::UnsatisfiableDependencyError.new req, [platform_entry]

    assert_match(/No match for/, error.message)
    assert_match(/java/, error.message)
    assert_equal req, error.dependency
  end
end
