# frozen_string_literal: true

require "spec_helper"
require "bundler/errors"

RSpec.describe Bundler::BundlerError do
  describe "base class" do
    it "inherits from StandardError and is a kind of StandardError" do
      error = Bundler::BundlerError.new("base error")
      expect(error).to be_a(StandardError)
      expect(error).to be_kind_of(StandardError)
    end

    it "stores and returns the provided message" do
      error = Bundler::BundlerError.new("test message")
      expect(error.message).to eq("test message")
      expect(error.to_s).to eq("test message")
    end
  end

  describe ".all_errors" do
    it "returns a hash that maps error classes to their status codes" do
      registry = Bundler::BundlerError.all_errors
      expect(registry).to be_a(Hash)
      expect(registry).not_to be_empty
    end

    it "includes all registered error subclasses with integer status codes" do
      registry = Bundler::BundlerError.all_errors
      registry.each do |klass, code|
        expect(klass).to be_a(Class)
        expect(code).to be_a(Integer)
      end
    end
  end

  describe ".status_code" do
    it "defines an instance method returning the assigned code on subclasses" do
      error = Bundler::GemfileError.new("test")
      expect(error).to respond_to(:status_code)
      expect(error.status_code).to be_a(Integer)
    end
  end
end

RSpec.describe "Bundler error hierarchy" do
  context "simple error subclasses inheriting from BundlerError" do
    {
      Bundler::GemfileError => 4,
      Bundler::InstallError => 5,
      Bundler::SolveFailure => 6,
      Bundler::GemNotFound => 7,
      Bundler::InstallHookError => 8,
      Bundler::RemovedError => 9,
      Bundler::GemfileNotFound => 10,
      Bundler::GitError => 11,
      Bundler::DeprecatedError => 12,
      Bundler::PathError => 13,
      Bundler::GemspecError => 14,
      Bundler::InvalidOption => 15,
      Bundler::ProductionError => 16,
      Bundler::RubyVersionMismatch => 18,
      Bundler::SecurityError => 19,
      Bundler::LockfileError => 20,
      Bundler::CyclicDependencyError => 21,
      Bundler::GemfileLockNotFound => 22,
      Bundler::PluginError => 29,
      Bundler::ThreadCreationError => 33,
      Bundler::APIResponseMismatchError => 34,
      Bundler::APIResponseInvalidDependenciesError => 35,
      Bundler::InvalidArgumentError => 40,
    }.each do |error_class, expected_code|
      describe error_class.name do
        it "is a kind of BundlerError and returns status_code #{expected_code}" do
          error = error_class.new("test error")
          expect(error).to be_a(Bundler::BundlerError)
          expect(error.status_code).to eq(expected_code)
        end

        it "is a kind of StandardError through BundlerError" do
          error = error_class.new("test error")
          expect(error).to be_a(StandardError)
          expect(error).to be_kind_of(Bundler::BundlerError)
        end

        it "is registered in the all_errors registry" do
          registry = Bundler::BundlerError.all_errors
          expect(registry).to include(error_class)
          expect(registry[error_class]).to eq(expected_code)
        end
      end
    end
  end

  describe Bundler::GemfileEvalError do
    it "inherits from GemfileError rather than BundlerError directly" do
      error = Bundler::GemfileEvalError.new("eval failed")
      expect(error).to be_a(Bundler::GemfileError)
      expect(error).to be_a(Bundler::BundlerError)
    end

    it "shares status_code with GemfileError (4)" do
      error = Bundler::GemfileEvalError.new("eval failed")
      expect(error.status_code).to eq(4)
      expect(error.message).to eq("eval failed")
    end
  end

  describe Bundler::MarshalError do
    it "inherits from StandardError directly rather than BundlerError" do
      error = Bundler::MarshalError.new("bad marshal data")
      expect(error).to be_a(StandardError)
      expect(error).not_to be_a(Bundler::BundlerError)
    end

    it "stores and returns the provided message" do
      error = Bundler::MarshalError.new("corrupt data")
      expect(error.message).to eq("corrupt data")
      expect(error.to_s).to eq("corrupt data")
    end
  end
end

RSpec.describe Bundler::HTTPError do
  it "inherits from BundlerError and has status_code 17" do
    error = Bundler::HTTPError.new("connection failed")
    expect(error).to be_a(Bundler::BundlerError)
    expect(error.status_code).to eq(17)
  end

  describe "#filter_uri" do
    it "delegates to URICredentialsFilter.credential_filtered_uri and returns filtered result" do
      error = Bundler::HTTPError.new("request failed")
      filtered = "https://x-oauth-basic@example.com/repo"
      allow(Bundler::URICredentialsFilter).to receive(:credential_filtered_uri)
        .with("https://user:pass@example.com/repo")
        .and_return(filtered)
      result = error.filter_uri("https://user:pass@example.com/repo")
      expect(result).to eq(filtered)
      expect(result).not_to include("pass")
    end

    it "returns nil when given nil URI" do
      error = Bundler::HTTPError.new("request failed")
      allow(Bundler::URICredentialsFilter).to receive(:credential_filtered_uri)
        .with(nil)
        .and_return(nil)
      result = error.filter_uri(nil)
      expect(result).to be_nil
    end

    it "returns the same URI when no credentials are present" do
      error = Bundler::HTTPError.new("request failed")
      clean_uri = "https://example.com/gems"
      allow(Bundler::URICredentialsFilter).to receive(:credential_filtered_uri)
        .with(clean_uri)
        .and_return(clean_uri)
      result = error.filter_uri(clean_uri)
      expect(result).to eq(clean_uri)
      expect(result).to eq("https://example.com/gems")
    end
  end
end

RSpec.describe Bundler::ChecksumMismatchError do
  let(:existing_sources) { ["the lockfile"] }
  let(:checksum_sources) { ["gems.example.com"] }
  let(:existing) do
    double("existing",
      to_lock: "sha256=abc123",
      sources: existing_sources,
      removable?: true,
      removal_instructions: "  1. Delete the checksum from the lockfile\n")
  end
  let(:checksum) do
    double("checksum",
      to_lock: "sha256=def456",
      sources: checksum_sources,
      removable?: false,
      removal_instructions: "  1. Remove the cached gem\n")
  end

  it "inherits from SecurityError and has status_code 37" do
    error = Bundler::ChecksumMismatchError.new("my-gem-1.0", existing, checksum)
    expect(error).to be_a(Bundler::SecurityError)
    expect(error.status_code).to eq(37)
  end

  it "is also a kind of BundlerError through SecurityError" do
    error = Bundler::ChecksumMismatchError.new("my-gem-1.0", existing, checksum)
    expect(error).to be_a(Bundler::BundlerError)
    expect(error).to be_a(StandardError)
  end

  describe "#message" do
    it "includes the lock_name, existing checksum info, and new checksum info" do
      error = Bundler::ChecksumMismatchError.new("my-gem-1.0", existing, checksum)
      msg = error.message
      expect(msg).to include("my-gem-1.0")
      expect(msg).to include("sha256=abc123")
      expect(msg).to include("sha256=def456")
    end

    it "includes source information from both existing and checksum objects" do
      error = Bundler::ChecksumMismatchError.new("my-gem-1.0", existing, checksum)
      msg = error.message
      expect(msg).to include("the lockfile")
      expect(msg).to include("gems.example.com")
    end

    it "includes the security risk warning and disable instructions" do
      error = Bundler::ChecksumMismatchError.new("my-gem-1.0", existing, checksum)
      msg = error.message
      expect(msg).to include("Bundler found mismatched checksums")
      expect(msg).to include("potential security risk")
      expect(msg).to include("bundle config set --local disable_checksum_validation true")
    end
  end

  describe "#mismatch_resolution_instructions" do
    context "when one checksum is removable" do
      it "includes trust message and removal instructions for the removable checksum" do
        error = Bundler::ChecksumMismatchError.new("my-gem-1.0", existing, checksum)
        instructions = error.mismatch_resolution_instructions
        expect(instructions).to include("If you trust")
        expect(instructions).to include("Delete the checksum from the lockfile")
      end
    end

    context "when both checksums are removable" do
      let(:checksum) do
        double("checksum",
          to_lock: "sha256=def456",
          sources: checksum_sources,
          removable?: true,
          removal_instructions: "  1. Remove the cached gem\n")
      end

      it "includes instructions for resolving in either direction" do
        error = Bundler::ChecksumMismatchError.new("my-gem-1.0", existing, checksum)
        instructions = error.mismatch_resolution_instructions
        expect(instructions).to include("To resolve this issue you can either")
        expect(instructions).to include("Remove the cached gem")
      end
    end
  end
end

RSpec.describe Bundler::PermissionError do
  describe "with default write permission type" do
    let(:error) { Bundler::PermissionError.new("/some/path") }

    it "inherits from BundlerError and has status_code 23" do
      expect(error).to be_a(Bundler::BundlerError)
      expect(error.status_code).to eq(23)
    end

    it "returns 'write to' as the action for default permission_type" do
      expect(error.action).to eq("write to")
      expect(error.action).to be_a(String)
    end

    it "formats the message with the path and write permission info" do
      msg = error.message
      expect(msg).to include("/some/path")
      expect(msg).to include("write to")
      expect(msg).to include("write permissions for that path")
    end

    it "returns write permission_type description" do
      expect(error.permission_type).to eq("write permissions for that path")
      expect(error.permission_type).to include("write")
    end
  end

  describe "with read permission type" do
    let(:error) { Bundler::PermissionError.new("/read/path", :read) }

    it "returns 'read from' as the action" do
      expect(error.action).to eq("read from")
      expect(error.message).to include("read from")
    end

    it "returns read permission_type description" do
      expect(error.permission_type).to eq("read permissions for that path")
      expect(error.permission_type).to include("read")
    end
  end

  describe "with executable permission type" do
    let(:error) { Bundler::PermissionError.new("/exec/path", :executable) }

    it "returns 'execute' as the action" do
      expect(error.action).to eq("execute")
      expect(error.message).to include("execute")
    end

    it "returns executable permission_type description" do
      expect(error.permission_type).to eq("executable permissions for that path")
      expect(error.permission_type).to include("executable")
    end
  end

  describe "with exec permission type" do
    let(:error) { Bundler::PermissionError.new("/exec/path", :exec) }

    it "returns 'execute' as the action" do
      expect(error.action).to eq("execute")
      expect(error.message).to include("execute")
    end
  end

  describe "with create permission type" do
    let(:error) { Bundler::PermissionError.new("/create/sub/path", :create) }

    it "returns 'create' as the action string" do
      expect(error.action).to eq("create")
      expect(error.action).to be_a(String)
    end

    it "returns executable permissions message referencing parent folder" do
      perm = error.permission_type
      expect(perm).to include("executable permissions for all parent directories")
      expect(perm).to include("/create/sub")
    end
  end

  describe "#message structure" do
    it "always contains the error preamble and permission guidance" do
      error = Bundler::PermissionError.new("/test/dir", :write)
      msg = error.message
      expect(msg).to include("There was an error while trying to")
      expect(msg).to include("It is likely that you need to grant")
    end
  end
end

RSpec.describe Bundler::GemRequireError do
  let(:orig_error) do
    begin
      raise LoadError, "cannot load such file -- missing_gem"
    rescue LoadError => e
      e
    end
  end

  it "inherits from BundlerError and has status_code 24" do
    error = Bundler::GemRequireError.new(orig_error, "Could not require missing_gem")
    expect(error).to be_a(Bundler::BundlerError)
    expect(error.status_code).to eq(24)
  end

  it "stores the original exception and makes it accessible" do
    error = Bundler::GemRequireError.new(orig_error, "Could not require missing_gem")
    expect(error.orig_exception).to be(orig_error)
    expect(error.orig_exception).to be_a(LoadError)
  end

  it "composes a message including the original error message and backtrace" do
    error = Bundler::GemRequireError.new(orig_error, "Could not require missing_gem")
    msg = error.message
    expect(msg).to include("Could not require missing_gem")
    expect(msg).to include("Gem Load Error is: cannot load such file -- missing_gem")
    expect(msg).to include("Backtrace for gem load error is:")
  end
end

RSpec.describe Bundler::YamlSyntaxError do
  let(:orig_error) { StandardError.new("syntax error at line 5") }

  it "inherits from BundlerError and has status_code 25" do
    error = Bundler::YamlSyntaxError.new(orig_error, "YAML parsing failed")
    expect(error).to be_a(Bundler::BundlerError)
    expect(error.status_code).to eq(25)
  end

  it "stores the original exception and returns the provided message" do
    error = Bundler::YamlSyntaxError.new(orig_error, "YAML parsing failed")
    expect(error.orig_exception).to be(orig_error)
    expect(error.message).to eq("YAML parsing failed")
  end

  it "preserves the original exception class" do
    error = Bundler::YamlSyntaxError.new(orig_error, "bad yaml")
    expect(error.orig_exception).to be_a(StandardError)
    expect(error.orig_exception.message).to eq("syntax error at line 5")
  end
end

RSpec.describe Bundler::TemporaryResourceError do
  let(:error) { Bundler::TemporaryResourceError.new("/tmp/resource") }

  it "inherits from PermissionError and has status_code 26" do
    expect(error).to be_a(Bundler::PermissionError)
    expect(error.status_code).to eq(26)
  end

  it "is also a kind of BundlerError through PermissionError" do
    expect(error).to be_a(Bundler::BundlerError)
    expect(error).to be_a(StandardError)
  end

  it "formats the message with the path and temporary resource language" do
    msg = error.message
    expect(msg).to include("/tmp/resource")
    expect(msg).to include("temporarily unavailable")
    expect(msg).to include("try")
  end
end

RSpec.describe Bundler::VirtualProtocolError do
  it "inherits from BundlerError and has status_code 27" do
    error = Bundler::VirtualProtocolError.new
    expect(error).to be_a(Bundler::BundlerError)
    expect(error.status_code).to eq(27)
  end

  it "returns a message about virtualization and file access" do
    error = Bundler::VirtualProtocolError.new
    msg = error.message
    expect(msg).to include("virtualization")
    expect(msg).to include("file access")
    expect(msg).to include("grant access")
  end
end

RSpec.describe Bundler::OperationNotSupportedError do
  let(:error) { Bundler::OperationNotSupportedError.new("/unsupported/path") }

  it "inherits from PermissionError and has status_code 28" do
    expect(error).to be_a(Bundler::PermissionError)
    expect(error.status_code).to eq(28)
  end

  it "formats the message with 'unsupported by your OS' and the path" do
    msg = error.message
    expect(msg).to include("/unsupported/path")
    expect(msg).to include("unsupported by your OS")
  end
end

RSpec.describe Bundler::NoSpaceOnDeviceError do
  let(:error) { Bundler::NoSpaceOnDeviceError.new("/full/disk/path") }

  it "inherits from PermissionError and has status_code 31" do
    expect(error).to be_a(Bundler::PermissionError)
    expect(error.status_code).to eq(31)
  end

  it "formats the message about insufficient space with the path" do
    msg = error.message
    expect(msg).to include("/full/disk/path")
    expect(msg).to include("insufficient space")
  end
end

RSpec.describe Bundler::ReadOnlyFileSystemError do
  let(:error) { Bundler::ReadOnlyFileSystemError.new("/readonly/path") }

  it "inherits from PermissionError and has status_code 42" do
    expect(error).to be_a(Bundler::PermissionError)
    expect(error.status_code).to eq(42)
  end

  it "formats the message about read-only file system with the path" do
    msg = error.message
    expect(msg).to include("/readonly/path")
    expect(msg).to include("read-only")
  end
end

RSpec.describe Bundler::OperationNotPermittedError do
  let(:error) { Bundler::OperationNotPermittedError.new("/restricted/path") }

  it "inherits from PermissionError and has status_code 43" do
    expect(error).to be_a(Bundler::PermissionError)
    expect(error.status_code).to eq(43)
  end

  it "formats the message about EPERM error with the path" do
    msg = error.message
    expect(msg).to include("/restricted/path")
    expect(msg).to include("EPERM")
  end
end

RSpec.describe Bundler::GenericSystemCallError do
  let(:underlying) { Errno::ENOENT.new("No such file - /missing/file") }

  it "inherits from BundlerError and has status_code 32" do
    error = Bundler::GenericSystemCallError.new(underlying, "System call failed")
    expect(error).to be_a(Bundler::BundlerError)
    expect(error.status_code).to eq(32)
  end

  it "stores the underlying error and makes it accessible" do
    error = Bundler::GenericSystemCallError.new(underlying, "System call failed")
    expect(error.underlying_error).to be(underlying)
    expect(error.underlying_error).to be_a(Errno::ENOENT)
  end

  it "composes a message that includes both the custom text and underlying error details" do
    error = Bundler::GenericSystemCallError.new(underlying, "System call failed")
    msg = error.message
    expect(msg).to include("System call failed")
    expect(msg).to include("Errno::ENOENT")
  end
end

RSpec.describe Bundler::DirectoryRemovalError do
  let(:orig_error) do
    begin
      raise Errno::EACCES, "Permission denied @ dir_s_rmdir - /locked/dir"
    rescue Errno::EACCES => e
      e
    end
  end

  it "inherits from BundlerError and has status_code 36" do
    error = Bundler::DirectoryRemovalError.new(orig_error, "Failed to remove directory")
    expect(error).to be_a(Bundler::BundlerError)
    expect(error.status_code).to eq(36)
  end

  it "composes a message with the original error info and backtrace" do
    error = Bundler::DirectoryRemovalError.new(orig_error, "Failed to remove directory")
    msg = error.message
    expect(msg).to include("Failed to remove directory")
    expect(msg).to include("Errno::EACCES")
    expect(msg).to include("Bundler Error Backtrace")
  end
end

RSpec.describe Bundler::InsecureInstallPathError do
  it "inherits from BundlerError and has status_code 38" do
    error = Bundler::InsecureInstallPathError.new("my-gem", "/world-writable/path/my-gem-1.0")
    expect(error).to be_a(Bundler::BundlerError)
    expect(error.status_code).to eq(38)
  end

  it "formats a message about insecure path with the gem name and path details" do
    error = Bundler::InsecureInstallPathError.new("my-gem", "/world-writable/path/my-gem-1.0")
    msg = error.message
    expect(msg).to include("my-gem")
    expect(msg).to include("/world-writable/path/my-gem-1.0")
    expect(msg).to include("world-writable")
    expect(msg).to include("sticky bit")
  end

  it "suggests changing permissions of the parent directory" do
    error = Bundler::InsecureInstallPathError.new("my-gem", "/world-writable/path/my-gem-1.0")
    msg = error.message
    expect(msg).to include("change the permissions")
    expect(msg).to include("/world-writable/path")
  end
end

RSpec.describe Bundler::CorruptBundlerInstallError do
  let(:loaded_spec) { double("loaded_spec", version: "2.3.4") }

  it "inherits from BundlerError and has status_code 39" do
    error = Bundler::CorruptBundlerInstallError.new(loaded_spec)
    expect(error).to be_a(Bundler::BundlerError)
    expect(error.status_code).to eq(39)
  end

  it "formats a message referencing both running and installed versions" do
    error = Bundler::CorruptBundlerInstallError.new(loaded_spec)
    msg = error.message
    expect(msg).to include(Bundler::VERSION)
    expect(msg).to include("2.3.4")
    expect(msg).to include("does not match")
  end

  it "suggests reinstalling Ruby to fix the problem" do
    error = Bundler::CorruptBundlerInstallError.new(loaded_spec)
    msg = error.message
    expect(msg).to include("Reinstalling Ruby")
    expect(msg).to include("fix the problem")
  end
end

RSpec.describe Bundler::IncorrectLockfileDependencies do
  let(:spec) { double("spec", full_name: "my-gem-1.0.0") }

  it "inherits from BundlerError and has status_code 41" do
    error = Bundler::IncorrectLockfileDependencies.new(spec)
    expect(error).to be_a(Bundler::BundlerError)
    expect(error.status_code).to eq(41)
  end

  it "stores the spec and makes it accessible" do
    error = Bundler::IncorrectLockfileDependencies.new(spec)
    expect(error.spec).to be(spec)
    expect(error.spec.full_name).to eq("my-gem-1.0.0")
  end

  it "formats a message referencing the spec full_name" do
    error = Bundler::IncorrectLockfileDependencies.new(spec)
    msg = error.message
    expect(msg).to include("incorrect dependencies")
    expect(msg).to include("my-gem-1.0.0")
    expect(msg).to include("lockfile")
  end
end

RSpec.describe "status code uniqueness" do
  it "assigns unique status codes to each registered error class" do
    registry = Bundler::BundlerError.all_errors
    codes = registry.values
    expect(codes.length).to eq(codes.uniq.length)
    expect(codes).to all(be_a(Integer))
  end

  it "contains all expected error classes in the registry" do
    registry = Bundler::BundlerError.all_errors
    expected_classes = [
      Bundler::GemfileError,
      Bundler::InstallError,
      Bundler::SolveFailure,
      Bundler::GemNotFound,
      Bundler::InstallHookError,
      Bundler::RemovedError,
      Bundler::GemfileNotFound,
      Bundler::GitError,
      Bundler::DeprecatedError,
      Bundler::PathError,
      Bundler::GemspecError,
      Bundler::InvalidOption,
      Bundler::ProductionError,
      Bundler::HTTPError,
      Bundler::RubyVersionMismatch,
      Bundler::SecurityError,
      Bundler::LockfileError,
      Bundler::CyclicDependencyError,
      Bundler::GemfileLockNotFound,
      Bundler::PluginError,
      Bundler::ThreadCreationError,
      Bundler::APIResponseMismatchError,
      Bundler::APIResponseInvalidDependenciesError,
      Bundler::ChecksumMismatchError,
      Bundler::PermissionError,
      Bundler::GemRequireError,
      Bundler::YamlSyntaxError,
      Bundler::TemporaryResourceError,
      Bundler::VirtualProtocolError,
      Bundler::OperationNotSupportedError,
      Bundler::NoSpaceOnDeviceError,
      Bundler::GenericSystemCallError,
      Bundler::DirectoryRemovalError,
      Bundler::InsecureInstallPathError,
      Bundler::CorruptBundlerInstallError,
      Bundler::InvalidArgumentError,
      Bundler::IncorrectLockfileDependencies,
      Bundler::ReadOnlyFileSystemError,
      Bundler::OperationNotPermittedError,
    ]
    expected_classes.each do |klass|
      expect(registry.keys).to include(klass)
    end
  end
end

RSpec.describe "PermissionError subclass message formatting" do
  context "with read permission type" do
    it "formats correctly for OperationNotSupportedError" do
      error = Bundler::OperationNotSupportedError.new("/test/path", :read)
      expect(error.message).to include("read from")
      expect(error.message).to include("/test/path")
    end

    it "formats correctly for NoSpaceOnDeviceError" do
      error = Bundler::NoSpaceOnDeviceError.new("/test/path", :read)
      expect(error.message).to include("read from")
      expect(error.message).to include("insufficient space")
    end
  end

  context "with executable permission type" do
    it "formats correctly for TemporaryResourceError" do
      error = Bundler::TemporaryResourceError.new("/test/bin", :executable)
      expect(error.message).to include("execute")
      expect(error.message).to include("temporarily unavailable")
    end

    it "formats correctly for ReadOnlyFileSystemError" do
      error = Bundler::ReadOnlyFileSystemError.new("/test/bin", :executable)
      expect(error.message).to include("execute")
      expect(error.message).to include("read-only")
    end
  end

  context "with default write permission type" do
    it "formats correctly for OperationNotPermittedError" do
      error = Bundler::OperationNotPermittedError.new("/test/path")
      expect(error.message).to include("write to")
      expect(error.message).to include("EPERM")
    end
  end
end
