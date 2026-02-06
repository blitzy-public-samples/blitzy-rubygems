# Technical Specification

# 0. Agent Action Plan

## 0.1 Intent Clarification

### 0.1.1 Core Testing Objective

Based on the provided requirements, the Blitzy platform understands that the testing objective is to **generate test coverage across the RubyGems/Bundler repository by importing and invoking existing production code directly from source modules, with strict prohibition against reimplementing any business logic within test files**.

**Request Category:** Add new tests | Improve coverage

The user requirements decompose into the following precise testing mandates:

- **Direct production invocation**: Every test must import and call real production functions, methods, and classes from their source modules (e.g., `require "rubygems/specification_policy"` followed by direct invocation of `Gem::SpecificationPolicy` methods)
- **Structural purity**: Test files must contain exclusively four categories of code — imports, test setup/fixtures, production function invocation, and assertions — with zero lines of reimplemented business logic
- **Selective mocking**: External dependencies (network I/O, file system operations, external APIs) may be mocked, but internal functions under test must never be stubbed or replaced
- **Validation enforcement**: Each test file must pass an automated review gate confirming zero lines of duplicated algorithms or business logic from production code
- **Coverage gap closure**: Production files identified as lacking dedicated test counterparts must receive new test files that exercise their public interfaces

**Implicit Testing Needs Surfaced:**
- Edge case coverage for untested utility modules (e.g., `GemspecHelpers`, `TargetRbConfig`, `PsychTree`)
- Error handling paths in complex modules (e.g., `S3URISigner` AWS SigV4 signing failures, `SpecificationPolicy` validation rejections)
- Boundary conditions in resolver components (`CurrentSet`, `SourceSet`, `Stats` modules)
- Return value validation for abstract base classes like `BasicSpecification`

### 0.1.2 Special Instructions and Constraints

**CRITICAL Directives from User:**

- **Forbidden Patterns (Verbatim from user):**
  - Copying function logic into test files
  - Creating test-local implementations that duplicate production behavior
  - Mocking internal functions under test

- **Validation Gate (Verbatim from user):** "Each test file must contain zero lines of business logic implementation. Any test containing reimplemented business logic or duplicated algorithms fails review automatically."

- **Test Structure Constraint:** Test files are restricted to containing only:
  - `require` / `import` statements pulling in production modules
  - Test setup blocks (`setup`, `teardown`, `before`, `after`, `let`)
  - Direct invocations of production functions with controlled inputs
  - Assertions validating outputs and side effects

- **Mocking Policy:** Mock or stub ONLY external dependencies including APIs, databases, file systems, and external services. Internal module methods and functions being tested must be called directly without interception.

### 0.1.3 Technical Interpretation

These testing requirements translate to the following technical test implementation strategy:

- To **test RubyGems core modules**, we will create new `Test::Unit` test files under `test/rubygems/` that `require` the production source, instantiate real objects, invoke real methods, and assert against the returned values — following the established `Gem::TestCase` inheritance pattern found in existing tests like `test_gem_version.rb`
- To **test Bundler core modules**, we will create new `RSpec` spec files under `bundler/spec/bundler/` that `require` the production source and use `describe`/`context`/`it` blocks to invoke real methods — following the established patterns in existing specs like `bundler/spec/bundler/dsl_spec.rb`
- To **mock external dependencies**, we will use the repository's established mocking infrastructure: `Gem::FakeFetcher` and `Gem::MockGemUi` for RubyGems, and Bundler's built-in `Artifice` for network isolation — never stubbing the module under test
- To **close coverage gaps**, we will target the 21 root-level RubyGems source files, 3 command files, 5 resolver modules, and high-priority Bundler source files that currently lack dedicated test counterparts
- To **validate test purity**, each test file will be auditable: every non-import, non-assertion line must be a direct call to a production method or test setup configuring inputs/fixtures

### 0.1.4 Coverage Requirements Interpretation

**Explicit Coverage Targets:** The user has not specified numeric coverage percentages. The implicit mandate is comprehensive: every production file should have at least one dedicated test file exercising its public interface.

**Implicit Coverage Expectations Based on Repository Analysis:**
- The existing repository demonstrates thorough coverage for core modules (136 RubyGems test files for 71 source files), indicating a high standard of coverage
- Industry standard for a package manager of this criticality: branch coverage above 80% for public APIs
- Critical path analysis identifies `SpecificationPolicy` (558 lines, validation logic), `S3URISigner` (226 lines, security-sensitive), `BasicSpecification` (393 lines, abstract base), and `QueryUtils` (349 lines, CLI interaction) as the highest-priority gaps

**To achieve comprehensive testing, coverage should include:**
- All public methods on untested classes
- All validation paths in `SpecificationPolicy`
- All signing scenarios in `S3URISigner` (valid credentials, expired tokens, malformed URIs)
- All abstract interface methods in `BasicSpecification` via concrete subclass instantiation
- All spell-check suggestion paths in `UnknownCommandSpellChecker`
- All YAML serialization/deserialization round-trips in `YAMLSerializer`


## 0.2 Test Discovery and Analysis

### 0.2.1 Existing Test Infrastructure Assessment

Repository analysis reveals a **dual-framework testing architecture** with mature infrastructure for both RubyGems (Test::Unit) and Bundler (RSpec), supported by extensive CI/CD matrix testing across multiple Ruby implementations and operating systems.

**RubyGems Testing Framework (`test/rubygems/`)**

- **Current testing framework:** Test::Unit version ~> 3.0 (latest compatible: 3.6.7)
- **Test runner configuration location:** `Rakefile` (defines `test` and `test:isolated` tasks), individual test files are self-runnable via `ruby -Ilib:test test/rubygems/test_gem_*.rb`
- **Test base class:** `Gem::TestCase` (defined in `test/rubygems/helper.rb`) — all RubyGems tests inherit from this class, which provides environment isolation, temporary directory management, and credential helpers
- **Coverage tools in use:** No dedicated coverage gem detected; coverage is implicitly managed through CI matrix completeness
- **Mock/stub libraries detected:**
  - `Gem::FakeFetcher` (`test/rubygems/utilities.rb`) — intercepts network requests and serves pre-configured gem data
  - `Gem::MockGemUi` (`test/rubygems/utilities.rb`) — captures stdout/stderr for CLI output validation
  - `Gem::StubSpecification` — lightweight specification doubles
- **Test data fixtures present:** `test/rubygems/data/` directory containing `.gemspec.rz` files, PEM certificates (`gem-private_key.pem`, `gem-public_cert.pem`), and pre-built gem archives for integration testing
- **Test naming convention:** `test_gem_<module_name>.rb` with class names following `TestGem<ModuleName> < Gem::TestCase`
- **Existing test count:** 136 test files in `test/rubygems/`

**Bundler Testing Framework (`bundler/spec/`)**

- **Current testing framework:** RSpec Core ~> 3.12, RSpec Expectations ~> 3.12, RSpec Mocks ~> 3.12
- **Test runner configuration location:** `bundler/spec/spec_helper.rb` for RSpec configuration; `tool/bundler/test_gems.rb` for dependency declarations
- **Parallel test support:** `turbo_tests ~> 2.2.3` and `parallel_tests ~> 4.10.1` for multi-process test execution
- **Mock/stub libraries detected:**
  - RSpec Mocks (built-in doubles and stubs)
  - `Artifice` — HTTP request interception for network isolation
  - Custom helpers in `bundler/spec/support/` — path helpers, build helpers, and gem builders
- **Test data fixtures present:** `bundler/spec/support/` directory containing fixture gems, Gemfile templates, and pre-built test scenarios
- **Test naming convention:** `<module_name>_spec.rb` with `RSpec.describe Bundler::<ModuleName>` blocks
- **Existing spec count:** 35 spec files in `bundler/spec/bundler/`

**CI/CD Testing Matrix (`.github/workflows/`)**

- **`rubygems.yml`** — Matrix: Ubuntu 24.04 / macOS 15 / Windows Server 2025 × Ruby 3.2 / 3.3 / 3.4 / JRuby / TruffleRuby
- **`bundler.yml`** — Parallel RSpec execution with turbo_tests across same platform matrix
- **Test isolation:** Each CI run uses clean gem home directories and temporary paths

### 0.2.2 Web Search Research Conducted

- **Test::Unit latest compatible version:** 3.6.7 (stable release December 2024) confirmed compatible with Ruby >= 3.2.0. The project specifies `~> 3.0` constraint in `tool/bundler/dev_gems.rb`, accommodating any 3.x release
- **RSpec 3.12 compatibility:** RSpec Core/Expectations/Mocks 3.12.x series is fully compatible with Ruby 3.2–3.4 and is the version pinned by the repository
- **Test::Unit best practices:** Tests should inherit from a shared base class (fulfilled by `Gem::TestCase`), use `setup`/`teardown` for fixture management, and employ `assert_*` methods for validation
- **Mocking strategy for RubyGems:** The established `Gem::FakeFetcher` pattern is the recommended approach for network isolation in the RubyGems test suite — external HTTP calls should be intercepted at the fetcher level, not at the method level of the class under test


## 0.3 Testing Scope Analysis

### 0.3.1 Test Target Identification

**Primary Code to Be Tested — RubyGems Core Modules (Highest Priority)**

| Module/Class | Path | Lines | Test Type Required |
|---|---|---|---|
| `Gem::SpecificationPolicy` | `lib/rubygems/specification_policy.rb` | 558 | Unit tests for all validation methods |
| `Gem::BasicSpecification` | `lib/rubygems/basic_specification.rb` | 393 | Unit tests via concrete subclass |
| `Gem::QueryUtils` | `lib/rubygems/query_utils.rb` | 349 | Unit tests for query formatting |
| `Gem::Defaults` | `lib/rubygems/defaults.rb` | 308 | Unit tests for default value accessors |
| `Gem::Exceptions` | `lib/rubygems/exceptions.rb` | 284 | Unit tests for exception hierarchy |
| `Gem::S3URISigner` | `lib/rubygems/s3_uri_signer.rb` | 226 | Unit tests for AWS SigV4 signing |
| `Gem::SpecificationRecord` | `lib/rubygems/specification_record.rb` | 212 | Unit tests for spec registry |
| `Gem::Errors` | `lib/rubygems/errors.rb` | 177 | Unit tests for error classes |
| `Gem::Deprecate` | `lib/rubygems/deprecate.rb` | 171 | Unit tests for deprecation warnings |
| `Gem::YAMLSerializer` | `lib/rubygems/yaml_serializer.rb` | 98 | Unit tests for serialization |
| `Gem::UserInteraction` | `lib/rubygems/user_interaction.rb` | 650 | Unit tests for I/O helpers |
| `Gem::TargetRbConfig` | `lib/rubygems/target_rbconfig.rb` | 50 | Unit tests for config wrapping |
| `Gem::SecurityOption` | `lib/rubygems/security_option.rb` | 43 | Unit tests for security flags |
| `Gem::PsychTree` | `lib/rubygems/psych_tree.rb` | 37 | Unit tests for YAML visitor |
| `Gem::InstallerUninstallerUtils` | `lib/rubygems/installer_uninstaller_utils.rb` | 27 | Unit tests for plugin utils |
| `Gem::UnknownCommandSpellChecker` | `lib/rubygems/unknown_command_spell_checker.rb` | 21 | Unit tests for suggestions |
| `Gem::GemspecHelpers` | `lib/rubygems/gemspec_helpers.rb` | 19 | Unit tests for gemspec discovery |

**Primary Code to Be Tested — RubyGems Commands**

| Module/Class | Path | Lines | Test Type Required |
|---|---|---|---|
| `Gem::Commands::GenerateIndexCommand` | `lib/rubygems/commands/generate_index_command.rb` | 51 | Unit tests for index generation CLI |
| `Gem::Commands::MirrorCommand` | `lib/rubygems/commands/mirror_command.rb` | 26 | Unit tests for mirror CLI |
| `Gem::Commands::RdocCommand` | `lib/rubygems/commands/rdoc_command.rb` | 90 | Unit tests for rdoc generation CLI |

**Primary Code to Be Tested — RubyGems Resolver**

| Module/Class | Path | Lines | Test Type Required |
|---|---|---|---|
| `Gem::Resolver::Set` | `lib/rubygems/resolver/set.rb` | 55 | Unit tests for base set behavior |
| `Gem::Resolver::CurrentSet` | `lib/rubygems/resolver/current_set.rb` | 12 | Unit tests for installed gem lookup |
| `Gem::Resolver::SourceSet` | `lib/rubygems/resolver/source_set.rb` | 47 | Unit tests for source management |
| `Gem::Resolver::SpecSpecification` | `lib/rubygems/resolver/spec_specification.rb` | 76 | Unit tests for spec wrapping |
| `Gem::Resolver::Stats` | `lib/rubygems/resolver/stats.rb` | 46 | Unit tests for resolution statistics |

**Primary Code to Be Tested — Bundler (High Priority, Non-Vendored)**

| Module/Class | Path | Lines | Test Type Required |
|---|---|---|---|
| `Bundler::Resolver` | `bundler/lib/bundler/resolver.rb` | 524 | RSpec unit tests for resolution |
| `Bundler::RubygemsExt` | `bundler/lib/bundler/rubygems_ext.rb` | 481 | RSpec unit tests for extensions |
| `Bundler::Runtime` | `bundler/lib/bundler/runtime.rb` | 320 | RSpec unit tests for runtime setup |
| `Bundler::Injector` | `bundler/lib/bundler/injector.rb` | 285 | RSpec unit tests for gem injection |
| `Bundler::Errors` | `bundler/lib/bundler/errors.rb` | 277 | RSpec unit tests for error classes |
| `Bundler::Checksum` | `bundler/lib/bundler/checksum.rb` | 270 | RSpec unit tests for checksum validation |
| `Bundler::LazySpecification` | `bundler/lib/bundler/lazy_specification.rb` | 245 | RSpec unit tests for lazy loading |
| `Bundler::Installer` | `bundler/lib/bundler/installer.rb` | 238 | RSpec unit tests for install orchestration |
| `Bundler::SelfManager` | `bundler/lib/bundler/self_manager.rb` | 196 | RSpec unit tests for self-update |
| `Bundler::RubygemsGemInstaller` | `bundler/lib/bundler/rubygems_gem_installer.rb` | 172 | RSpec unit tests for gem installation |
| `Bundler::LockfileGenerator` | `bundler/lib/bundler/lockfile_generator.rb` | 104 | RSpec unit tests for lockfile writing |
| `Bundler::Inline` | `bundler/lib/bundler/inline.rb` | 98 | RSpec unit tests for inline bundler |
| `Bundler::CompactIndexClient` | `bundler/lib/bundler/compact_index_client.rb` | 93 | RSpec unit tests for index parsing |
| `Bundler::SourceMap` | `bundler/lib/bundler/source_map.rb` | 68 | RSpec unit tests for source mapping |
| `Bundler::SimilarityDetector` | `bundler/lib/bundler/similarity_detector.rb` | 63 | RSpec unit tests for fuzzy matching |
| `Bundler::Materialization` | `bundler/lib/bundler/materialization.rb` | 59 | RSpec unit tests for materialization |
| `Bundler::Deprecate` | `bundler/lib/bundler/deprecate.rb` | 44 | RSpec unit tests for deprecation |
| `Bundler::MatchPlatform` | `bundler/lib/bundler/match_platform.rb` | 42 | RSpec unit tests for platform matching |
| `Bundler::SafeMarshal` | `bundler/lib/bundler/safe_marshal.rb` | 31 | RSpec unit tests for safe deserialization |
| `Bundler::MatchMetadata` | `bundler/lib/bundler/match_metadata.rb` | 30 | RSpec unit tests for metadata matching |
| `Bundler::MatchRemoteMetadata` | `bundler/lib/bundler/match_remote_metadata.rb` | 29 | RSpec unit tests for remote metadata |
| `Bundler::URINormalizer` | `bundler/lib/bundler/uri_normalizer.rb` | 23 | RSpec unit tests for URI normalization |
| `Bundler::ProcessLock` | `bundler/lib/bundler/process_lock.rb` | 20 | RSpec unit tests for locking |
| `Bundler::FeatureFlag` | `bundler/lib/bundler/feature_flag.rb` | 20 | RSpec unit tests for feature flags |
| `Bundler::ForcePlatform` | `bundler/lib/bundler/force_platform.rb` | 16 | RSpec unit tests for platform forcing |

**Existing Test File Mapping (Representative Sample)**

| Source File | Existing Test File | Test Categories Present |
|---|---|---|
| `lib/rubygems/version.rb` | `test/rubygems/test_gem_version.rb` | Happy path, comparison, edge cases |
| `lib/rubygems/dependency.rb` | `test/rubygems/test_gem_dependency.rb` | Matching, requirements, operators |
| `lib/rubygems/specification.rb` | `test/rubygems/test_gem_specification.rb` | Full lifecycle, attributes, validation |
| `lib/rubygems/remote_fetcher.rb` | `test/rubygems/test_gem_remote_fetcher.rb` | Network mocking, download, cache |
| `lib/rubygems/installer.rb` | `test/rubygems/test_gem_installer.rb` | Install flows, wrappers, plugins |
| `lib/rubygems/safe_marshal.rb` | `test/rubygems/test_gem_safe_marshal.rb` | Safe deserialization, edge cases |
| `bundler/lib/bundler/dsl.rb` | `bundler/spec/bundler/dsl_spec.rb` | Gemfile parsing, DSL methods |
| `bundler/lib/bundler/definition.rb` | `bundler/spec/bundler/definition_spec.rb` | Dependency resolution, lockfile |
| `bundler/lib/bundler/source.rb` | `bundler/spec/bundler/source_spec.rb` | Source configuration, priorities |

**Dependencies Requiring Mocking**

- **External services to mock:** HTTP fetcher responses (via `Gem::FakeFetcher`), S3 API calls (for `S3URISigner`), RubyGems.org API responses
- **Database interactions to stub:** None — the repository uses file-system-based storage
- **File system operations to virtualize:** Gem installation paths (via `Gem::TestCase` temporary directories), lockfile I/O (via temporary paths), gemspec file discovery (via controlled directory structures)

### 0.3.2 Version Compatibility Research

Based on current Ruby version >= 3.2.0 (tested up to 3.4.5), the recommended testing stack is:

| Component | Name | Compatible Version | Rationale |
|---|---|---|---|
| Testing framework (RubyGems) | Test::Unit | ~> 3.0 (3.6.7 latest stable) | Pinned in `tool/bundler/dev_gems.rb`; backward-compatible across 3.x |
| Testing framework (Bundler) | RSpec Core | ~> 3.12 | Pinned in `tool/bundler/dev_gems.rb`; Ruby 3.2+ compatible |
| Matcher library | RSpec Expectations | ~> 3.12 | Bundled with RSpec Core |
| Mocking library | RSpec Mocks | ~> 3.12 | Bundled with RSpec Core |
| Parallel runner | turbo_tests | ~> 2.2.3 | Pinned in `tool/bundler/test_gems.rb` |
| HTTP test server | Sinatra | ~> 4.1 | Test infrastructure for Bundler integration tests |
| HTTP testing | Rack | ~> 3.1 | Required by Sinatra and test servers |
| Request testing | Rack-test | ~> 2.1 | HTTP request testing utilities |
| Build automation | Rake | ~> 13.1 | Task runner for test execution |

**Version Conflicts to Resolve:** None detected. All testing dependencies are mutually compatible and align with the repository's existing version pins. The `~>` pessimistic version operator ensures minor version updates are accepted while major version breakage is prevented.


## 0.4 Test Implementation Design

### 0.4.1 Test Strategy Selection

**Test types to implement:**

- **Unit tests:** Focus on isolated public method invocation for each untested production module. Every test instantiates real production objects, passes controlled inputs, and asserts on actual return values. No business logic is reproduced in the test file.
- **Edge case tests:** Address boundary conditions including nil inputs, empty collections, malformed strings, maximum-length arguments, and type mismatches for each module's public API.
- **Error handling tests:** Verify that production code raises the correct exception classes with appropriate messages when given invalid input, missing dependencies, or encountering I/O failures.
- **Integration tests (limited):** For resolver and installer modules where component interaction is essential to exercise the production code path, tests will invoke the real orchestration methods with mocked external I/O only.

### 0.4.2 Test Case Blueprint

**RubyGems Modules — Test::Unit Pattern**

```
Component: Gem::SpecificationPolicy
Test Categories:
- Happy path: Valid gemspec passes all validation checks
- Edge cases: Empty name, missing version, nil summary
- Error cases: Invalid license, bad homepage URL, oversized description
```

```
Component: Gem::S3URISigner
Test Categories:
- Happy path: Valid URI signed with correct credentials
- Edge cases: URI with special characters, empty path, port numbers
- Error cases: Expired credentials, missing secret key, malformed URI
```

```
Component: Gem::BasicSpecification
Test Categories:
- Happy path: Concrete subclass returns correct name, version, platform
- Edge cases: Default stub values, missing attributes
- Error cases: Abstract methods raise NotImplementedError
```

```
Component: Gem::YAMLSerializer
Test Categories:
- Happy path: Round-trip serialize/deserialize preserves data
- Edge cases: Empty hash, nested structures, special characters
- Error cases: Malformed YAML input
```

```
Component: Gem::UnknownCommandSpellChecker
Test Categories:
- Happy path: Misspelled command returns correct suggestions
- Edge cases: Empty input, single character, exact match
- Error cases: No similar commands found
```

```
Component: Gem::Resolver::Set (base class)
Test Categories:
- Happy path: find_all and prefetch respond correctly
- Edge cases: Empty specification list
- Error cases: Remote flag behavior
```

```
Component: Gem::Resolver::SourceSet
Test Categories:
- Happy path: Add and retrieve source specifications
- Edge cases: Duplicate sources, empty source list
- Error cases: Invalid source URI
```

```
Component: Gem::Resolver::Stats
Test Categories:
- Happy path: Record and display resolution statistics
- Edge cases: Zero requirements, single iteration
- Error cases: Display with no data
```

**Bundler Modules — RSpec Pattern**

```
Component: Bundler::Checksum
Test Categories:
- Happy path: Valid checksum verification passes
- Edge cases: Empty digest, nil input, multiple algorithms
- Error cases: Checksum mismatch raises error
```

```
Component: Bundler::SimilarityDetector
Test Categories:
- Happy path: Similar strings detected correctly
- Edge cases: Identical strings, completely different strings
- Error cases: Empty corpus
```

```
Component: Bundler::LockfileGenerator
Test Categories:
- Happy path: Generate valid lockfile content from definition
- Edge cases: Empty dependency list, single platform
- Error cases: Nil definition input
```

```
Component: Bundler::URINormalizer
Test Categories:
- Happy path: Normalize standard URIs correctly
- Edge cases: Trailing slashes, authentication credentials
- Error cases: Invalid URI format
```

```
Component: Bundler::ProcessLock
Test Categories:
- Happy path: Acquire and release lock successfully
- Edge cases: Nested lock attempts, immediate release
- Error cases: Lock file permissions
```

### 0.4.3 Existing Test Extension Strategy

- **Tests to extend:** Enhance `test/rubygems/test_gem_specification.rb` by adding cases that exercise `SpecificationPolicy` validation paths triggered during specification attribute assignment — ensuring the policy object is invoked through normal production flows rather than tested in isolation only
- **Tests to extend:** Enhance `test/rubygems/test_gem_installer.rb` by adding cases that exercise `InstallerUninstallerUtils.regenerate_plugins` through the standard install path
- **Tests to extend:** Enhance `test/rubygems/test_gem_safe_marshal.rb` by adding edge cases for `PsychTree` YAML visitor behavior during marshal round-trips
- **Tests to extend:** Enhance `bundler/spec/bundler/definition_spec.rb` by adding cases that exercise `LockfileGenerator` output through definition resolution
- **Tests to reference:** Use `test/rubygems/test_gem_version.rb` and `test/rubygems/test_gem_dependency.rb` as canonical examples of the production-invocation-only pattern for all new RubyGems tests
- **Tests to reference:** Use `bundler/spec/bundler/dsl_spec.rb` as the canonical example for all new Bundler specs

### 0.4.4 Test Data and Fixtures Design

**Required Test Data Structures:**

- **Gemspec fixtures:** Valid and invalid gemspec hashes for `SpecificationPolicy` validation testing (name, version, summary, license combinations)
- **URI fixtures:** Pre-constructed URI objects for `S3URISigner` and `URINormalizer` testing (standard HTTPS, S3 paths, authenticated URIs, malformed strings)
- **YAML fixtures:** Structured YAML strings and expected Ruby hash equivalents for `YAMLSerializer` round-trip testing
- **Command name fixtures:** Arrays of known command names and misspelled variants for `UnknownCommandSpellChecker` testing
- **Resolver fixtures:** `Gem::Resolver::DependencyRequest` and `Gem::Specification` instances for resolver set testing

**Fixture Organization Strategy:**

- RubyGems test fixtures remain in-line within test methods (following existing convention in the repository — no separate fixture files for unit tests)
- Complex test data uses `setup` method initialization
- Bundler spec fixtures use `let` blocks and `before` blocks following existing RSpec conventions in `bundler/spec/`
- Shared test data is defined in helper files only when used across multiple test files

**Mock Object Specifications:**

- `Gem::FakeFetcher` — Used for any test that would otherwise make HTTP requests (S3URISigner, remote source sets)
- `Gem::MockGemUi` — Used for capturing output in command tests (`GenerateIndexCommand`, `MirrorCommand`, `RdocCommand`)
- `StringIO` — Used as IO substitute for user interaction tests
- Bundler specs use RSpec doubles for external services only, with `allow().to receive()` syntax

**Test State Management:**

- Every RubyGems test inherits `Gem::TestCase` which provides automatic temporary directory creation (`@tempdir`), gem home isolation (`@gemhome`), and credential cleanup in `teardown`
- Every Bundler spec leverages the shared context in `spec_helper.rb` for path isolation
- No shared mutable state across test methods — each test is fully independent


## 0.5 Test File Transformation Mapping

### 0.5.1 File-by-File Test Plan

**RubyGems Core Module Tests — CREATE**

| Target Test File | Transformation | Source File/Test | Purpose/Changes |
|---|---|---|---|
| `test/rubygems/test_gem_specification_policy.rb` | CREATE | `lib/rubygems/specification_policy.rb` | Unit tests for all validation methods: `validate`, `validate_name`, `validate_version`, `validate_summary`, `validate_license`, homepage URL checking, and error/warning paths (558 lines of validation logic) |
| `test/rubygems/test_gem_basic_specification.rb` | CREATE | `lib/rubygems/basic_specification.rb` | Unit tests via concrete subclass for `gems_dir`, `base_dir`, `full_gem_path`, `gem_dir`, `loaded_from`, extension path methods, platform detection, and stub behavior (393 lines) |
| `test/rubygems/test_gem_query_utils.rb` | CREATE | `lib/rubygems/query_utils.rb` | Unit tests for query option parsing, output formatting, version listing, detail display, and platform filtering methods (349 lines) |
| `test/rubygems/test_gem_defaults.rb` | CREATE | `lib/rubygems/defaults.rb` | Unit tests for all default path accessors: `default_dir`, `default_path`, `default_bindir`, `default_cert_path`, `default_sources`, and platform-specific defaults (308 lines) |
| `test/rubygems/test_gem_exceptions.rb` | CREATE | `lib/rubygems/exceptions.rb` | Unit tests for exception class hierarchy, message formatting, custom attributes on `Gem::DependencyError`, `Gem::FormatException`, `Gem::GemNotFoundException`, and all other exception classes (284 lines) |
| `test/rubygems/test_gem_s3_uri_signer.rb` | CREATE | `lib/rubygems/s3_uri_signer.rb` | Unit tests for AWS SigV4 URI signing including canonical request construction, signature computation, credential scoping, session token handling, and error paths for invalid URIs (226 lines) |
| `test/rubygems/test_gem_specification_record.rb` | CREATE | `lib/rubygems/specification_record.rb` | Unit tests for spec registration, `find_by_name_and_version`, `find_all_by_name`, `stubs`, `stubs_for`, path-to-spec mapping, and record enumeration (212 lines) |
| `test/rubygems/test_gem_errors.rb` | CREATE | `lib/rubygems/errors.rb` | Unit tests for `Gem::UnsatisfizableDependencyError`, `Gem::OperationNotSupportedError`, and error message rendering with dependency context (177 lines) |
| `test/rubygems/test_gem_deprecate.rb` | CREATE | `lib/rubygems/deprecate.rb` | Unit tests for `Gem::Deprecate.deprecate` method, warning message generation, skip flag behavior, and module extension functionality (171 lines) |
| `test/rubygems/test_gem_yaml_serializer.rb` | CREATE | `lib/rubygems/yaml_serializer.rb` | Unit tests for `dump` and `load` methods with round-trip verification, multi-line values, special characters, and malformed input handling (98 lines) |
| `test/rubygems/test_gem_user_interaction.rb` | CREATE | `lib/rubygems/user_interaction.rb` | Unit tests for `alert`, `alert_warning`, `alert_error`, `ask`, `ask_yes_no`, `choose_from_list`, `say`, terminal width detection, and verbose/quiet mode toggle (650 lines) |
| `test/rubygems/test_gem_target_rbconfig.rb` | CREATE | `lib/rubygems/target_rbconfig.rb` | Unit tests for `RbConfig` wrapping, `[]` accessor, path resolution, and platform detection delegation (50 lines) |
| `test/rubygems/test_gem_security_option.rb` | CREATE | `lib/rubygems/security_option.rb` | Unit tests for security policy option flag parsing, `add_security_option` method, and policy name resolution (43 lines) |
| `test/rubygems/test_gem_psych_tree.rb` | CREATE | `lib/rubygems/psych_tree.rb` | Unit tests for YAML `Psych::Visitors::YAMLTree` subclass behavior, custom `visit_String` method, and encoding handling (37 lines) |
| `test/rubygems/test_gem_installer_uninstaller_utils.rb` | CREATE | `lib/rubygems/installer_uninstaller_utils.rb` | Unit tests for `regenerate_plugins` method, plugin path discovery, and file system operations (27 lines) |
| `test/rubygems/test_gem_unknown_command_spell_checker.rb` | CREATE | `lib/rubygems/unknown_command_spell_checker.rb` | Unit tests for `DidYouMean`-based command suggestion, `corrections` method, and empty suggestion handling (21 lines) |
| `test/rubygems/test_gem_gemspec_helpers.rb` | CREATE | `lib/rubygems/gemspec_helpers.rb` | Unit tests for `find_by_name` gemspec discovery, path searching, and nil return on missing gemspec (19 lines) |

**RubyGems Command Tests — CREATE**

| Target Test File | Transformation | Source File/Test | Purpose/Changes |
|---|---|---|---|
| `test/rubygems/test_gem_commands_generate_index_command.rb` | CREATE | `lib/rubygems/commands/generate_index_command.rb` | Unit tests for index generation command options, directory argument handling, and execute method invocation (51 lines) |
| `test/rubygems/test_gem_commands_rdoc_command.rb` | CREATE | `lib/rubygems/commands/rdoc_command.rb` | Unit tests for rdoc/ri generation command, `--all` flag, version selection, and overwrite option handling (90 lines) |

**RubyGems Resolver Tests — CREATE**

| Target Test File | Transformation | Source File/Test | Purpose/Changes |
|---|---|---|---|
| `test/rubygems/test_gem_resolver_set.rb` | CREATE | `lib/rubygems/resolver/set.rb` | Unit tests for base `Set` class `find_all`, `prefetch`, and `remote=` accessor behavior (55 lines) |
| `test/rubygems/test_gem_resolver_current_set.rb` | CREATE | `lib/rubygems/resolver/current_set.rb` | Unit tests for `find_all` against currently installed gems and specification matching (12 lines) |
| `test/rubygems/test_gem_resolver_source_set.rb` | CREATE | `lib/rubygems/resolver/source_set.rb` | Unit tests for `add_source_gem`, `find_all` with source filtering, and specification construction (47 lines) |
| `test/rubygems/test_gem_resolver_spec_specification.rb` | CREATE | `lib/rubygems/resolver/spec_specification.rb` | Unit tests for spec wrapping, dependency forwarding, `install` method, and platform handling (76 lines) |
| `test/rubygems/test_gem_resolver_stats.rb` | CREATE | `lib/rubygems/resolver/stats.rb` | Unit tests for `record_requirements`, `record_depth`, `display`, and counter accuracy (46 lines) |

**Bundler Spec Tests — CREATE**

| Target Test File | Transformation | Source File/Test | Purpose/Changes |
|---|---|---|---|
| `bundler/spec/bundler/resolver_spec.rb` | CREATE | `bundler/lib/bundler/resolver.rb` | RSpec unit tests for dependency resolution, conflict detection, platform filtering, and resolution result construction (524 lines) |
| `bundler/spec/bundler/rubygems_ext_spec.rb` | CREATE | `bundler/lib/bundler/rubygems_ext.rb` | RSpec unit tests for RubyGems monkey-patches, `Gem::Specification` extensions, and compatibility methods (481 lines) |
| `bundler/spec/bundler/runtime_spec.rb` | CREATE | `bundler/lib/bundler/runtime.rb` | RSpec unit tests for `#setup`, `#require`, gem activation, and load path management (320 lines) |
| `bundler/spec/bundler/injector_spec.rb` | CREATE | `bundler/lib/bundler/injector.rb` | RSpec unit tests for `inject_gems`, Gemfile modification, and dependency injection (285 lines) |
| `bundler/spec/bundler/errors_spec.rb` | CREATE | `bundler/lib/bundler/errors.rb` | RSpec unit tests for all Bundler error classes, message formatting, and status code assignment (277 lines) |
| `bundler/spec/bundler/checksum_spec.rb` | CREATE | `bundler/lib/bundler/checksum.rb` | RSpec unit tests for checksum computation, verification, store operations, and mismatch detection (270 lines) |
| `bundler/spec/bundler/lazy_specification_spec.rb` | CREATE | `bundler/lib/bundler/lazy_specification.rb` | RSpec unit tests for lazy loading, materialization trigger, identifier matching, and source association (245 lines) |
| `bundler/spec/bundler/installer_spec.rb` | CREATE | `bundler/lib/bundler/installer.rb` | RSpec unit tests for `#run`, parallel installation, post-install hooks, and standalone mode (238 lines) |
| `bundler/spec/bundler/self_manager_spec.rb` | CREATE | `bundler/lib/bundler/self_manager.rb` | RSpec unit tests for self-update detection, version switching, and restart logic (196 lines) |
| `bundler/spec/bundler/rubygems_gem_installer_spec.rb` | CREATE | `bundler/lib/bundler/rubygems_gem_installer.rb` | RSpec unit tests for gem installation, build args, and extension building (172 lines) |
| `bundler/spec/bundler/lockfile_generator_spec.rb` | CREATE | `bundler/lib/bundler/lockfile_generator.rb` | RSpec unit tests for lockfile string generation, platform section, and dependency formatting (104 lines) |
| `bundler/spec/bundler/inline_spec.rb` | CREATE | `bundler/lib/bundler/inline.rb` | RSpec unit tests for `gemfile` method, inline dependency resolution, and require behavior (98 lines) |
| `bundler/spec/bundler/compact_index_client_spec.rb` | CREATE | `bundler/lib/bundler/compact_index_client.rb` | RSpec unit tests for compact index parsing, incremental update, and endpoint construction (93 lines) |
| `bundler/spec/bundler/source_map_spec.rb` | CREATE | `bundler/lib/bundler/source_map.rb` | RSpec unit tests for source-to-dependency mapping, pinned sources, and default source resolution (68 lines) |
| `bundler/spec/bundler/similarity_detector_spec.rb` | CREATE | `bundler/lib/bundler/similarity_detector.rb` | RSpec unit tests for Levenshtein-like distance computation, suggestion ranking, and threshold filtering (63 lines) |
| `bundler/spec/bundler/materialization_spec.rb` | CREATE | `bundler/lib/bundler/materialization.rb` | RSpec unit tests for specification materialization, missing gem detection, and error reporting (59 lines) |
| `bundler/spec/bundler/deprecate_spec.rb` | CREATE | `bundler/lib/bundler/deprecate.rb` | RSpec unit tests for deprecation warning emission, replacement method indication, and skip behavior (44 lines) |
| `bundler/spec/bundler/match_platform_spec.rb` | CREATE | `bundler/lib/bundler/match_platform.rb` | RSpec unit tests for platform matching logic, `match_platform` method, and platform string normalization (42 lines) |
| `bundler/spec/bundler/safe_marshal_spec.rb` | CREATE | `bundler/lib/bundler/safe_marshal.rb` | RSpec unit tests for safe marshal load, class whitelist enforcement, and deserialization output (31 lines) |
| `bundler/spec/bundler/match_metadata_spec.rb` | CREATE | `bundler/lib/bundler/match_metadata.rb` | RSpec unit tests for metadata matching, required Ruby version check, and RubyGems version check (30 lines) |
| `bundler/spec/bundler/match_remote_metadata_spec.rb` | CREATE | `bundler/lib/bundler/match_remote_metadata.rb` | RSpec unit tests for remote metadata matching, version filtering, and platform requirements (29 lines) |
| `bundler/spec/bundler/uri_normalizer_spec.rb` | CREATE | `bundler/lib/bundler/uri_normalizer.rb` | RSpec unit tests for URI normalization, trailing slash handling, and credential preservation (23 lines) |
| `bundler/spec/bundler/process_lock_spec.rb` | CREATE | `bundler/lib/bundler/process_lock.rb` | RSpec unit tests for file-based locking, lock acquisition, release, and concurrent access safety (20 lines) |
| `bundler/spec/bundler/feature_flag_spec.rb` | CREATE | `bundler/lib/bundler/feature_flag.rb` | RSpec unit tests for feature flag registration, query methods, and default values (20 lines) |
| `bundler/spec/bundler/force_platform_spec.rb` | CREATE | `bundler/lib/bundler/force_platform.rb` | RSpec unit tests for `force_ruby_platform` flag behavior and platform override logic (16 lines) |

**Existing Test Files — UPDATE**

| Target Test File | Transformation | Source File/Test | Purpose/Changes |
|---|---|---|---|
| `test/rubygems/test_gem_specification.rb` | UPDATE | `test/rubygems/test_gem_specification.rb` | Add test cases exercising `SpecificationPolicy` validation through normal `Gem::Specification` attribute assignment paths |
| `test/rubygems/test_gem_installer.rb` | UPDATE | `test/rubygems/test_gem_installer.rb` | Add test cases exercising `InstallerUninstallerUtils.regenerate_plugins` through the standard install workflow |
| `test/rubygems/test_gem_safe_marshal.rb` | UPDATE | `test/rubygems/test_gem_safe_marshal.rb` | Add edge cases for `PsychTree` YAML visitor behavior during marshal round-trip operations |
| `test/rubygems/test_gem_commands_mirror.rb` | UPDATE | `test/rubygems/test_gem_commands_mirror.rb` | Verify comprehensive `MirrorCommand` coverage; add missing option and error path tests |
| `test/rubygems/test_gem_stream_ui.rb` | UPDATE | `test/rubygems/test_gem_stream_ui.rb` | Extend with additional `UserInteraction` module method coverage via `StreamUI` |
| `bundler/spec/bundler/definition_spec.rb` | UPDATE | `bundler/spec/bundler/definition_spec.rb` | Add test cases that exercise `LockfileGenerator` output through the definition resolution path |
| `bundler/spec/bundler/yaml_serializer_spec.rb` | UPDATE | `bundler/spec/bundler/yaml_serializer_spec.rb` | Extend with additional round-trip edge cases, special character handling, and malformed input tests |

**Reference Files — REFERENCE**

| Target Test File | Transformation | Source File/Test | Purpose/Changes |
|---|---|---|---|
| `test/rubygems/test_gem_version.rb` | REFERENCE | `test/rubygems/test_gem_version.rb` | Canonical example of Test::Unit test structure: direct production class import, `Gem::TestCase` inheritance, setup, assertion-only test methods |
| `test/rubygems/test_gem_dependency.rb` | REFERENCE | `test/rubygems/test_gem_dependency.rb` | Reference for helper method usage (`dep`, `req`) and multi-assertion test patterns |
| `test/rubygems/test_gem_remote_fetcher.rb` | REFERENCE | `test/rubygems/test_gem_remote_fetcher.rb` | Reference for `Gem::FakeFetcher` mocking pattern for external HTTP dependencies |
| `test/rubygems/test_gem_commands_build_command.rb` | REFERENCE | `test/rubygems/test_gem_commands_build_command.rb` | Reference for command test structure: `Gem::MockGemUi`, option setting, and execute invocation |
| `test/rubygems/test_gem_resolver_api_set.rb` | REFERENCE | `test/rubygems/test_gem_resolver_api_set.rb` | Reference for resolver test patterns: dependency request construction and set querying |
| `test/rubygems/helper.rb` | REFERENCE | `test/rubygems/helper.rb` | Test harness reference for `Gem::TestCase` base class, setup/teardown lifecycle, and utility methods |
| `test/rubygems/utilities.rb` | REFERENCE | `test/rubygems/utilities.rb` | Reference for `Gem::FakeFetcher` and `Gem::MockGemUi` implementations |
| `bundler/spec/bundler/dsl_spec.rb` | REFERENCE | `bundler/spec/bundler/dsl_spec.rb` | Canonical example of Bundler RSpec structure: `RSpec.describe`, `let` blocks, context organization |
| `bundler/spec/spec_helper.rb` | REFERENCE | `bundler/spec/spec_helper.rb` | Spec harness reference for RSpec configuration, shared contexts, and helper inclusions |

### 0.5.2 New Test Files Detail

**RubyGems New Test Files**

- `test/rubygems/test_gem_specification_policy.rb` — Comprehensive validation testing
  - Test categories: valid spec pass-through, name validation (empty, nil, special chars), version validation, summary/description validation, license SPDX validation, homepage URL format, required Ruby version, dependencies validation, warning-vs-error distinction
  - Mock dependencies: None (pure validation logic)
  - Assertions focus: `assert_equal`, `assert_raises`, `assert_match` on error messages, `assert_empty` for warnings collection

- `test/rubygems/test_gem_basic_specification.rb` — Abstract base class testing via concrete subclass
  - Test categories: `gems_dir` resolution, `base_dir` computation, `full_gem_path` construction, `loaded_from` attribute, extension path methods, `default_gem?` detection, platform accessor
  - Mock dependencies: File system paths (via `Gem::TestCase` temp dirs)
  - Assertions focus: `assert_equal` on path strings, `assert_respond_to` for interface methods

- `test/rubygems/test_gem_s3_uri_signer.rb` — AWS SigV4 signing
  - Test categories: URI parsing, canonical request construction, credential chain resolution, signature generation, session token inclusion, expiration handling
  - Mock dependencies: `Gem::FakeFetcher` for credential retrieval; environment variables for AWS credentials
  - Assertions focus: `assert_match` on signed URL patterns, `assert_raises` for invalid credential scenarios

- `test/rubygems/test_gem_yaml_serializer.rb` — YAML serialization round-trips
  - Test categories: simple hash dump/load, nested hash structures, multi-line string values, special character handling, empty input, malformed YAML recovery
  - Mock dependencies: None (pure data transformation)
  - Assertions focus: `assert_equal` on round-trip data, `assert_raises` for invalid input

- `test/rubygems/test_gem_unknown_command_spell_checker.rb` — Command suggestion
  - Test categories: close misspelling returns suggestion, distant misspelling returns empty, exact match, empty input, multiple similar commands
  - Mock dependencies: None (operates on string arrays)
  - Assertions focus: `assert_includes`, `assert_empty`, `assert_equal` on suggestion arrays

- `test/rubygems/test_gem_resolver_stats.rb` — Resolution statistics
  - Test categories: requirement recording, depth tracking, display output, zero-state behavior
  - Mock dependencies: `StringIO` for output capture
  - Assertions focus: `assert_match` on display output, counter value assertions

**Bundler New Spec Files**

- `bundler/spec/bundler/checksum_spec.rb` — Checksum validation
  - Test categories: SHA256 computation, digest comparison, store add/lookup, mismatch error raising
  - Mock dependencies: None for pure checksum logic; stubbed fetcher for remote checksums
  - Assertions focus: `expect().to eq()`, `expect().to raise_error()`

- `bundler/spec/bundler/similarity_detector_spec.rb` — Fuzzy string matching
  - Test categories: similar gem name detection, distance threshold, empty corpus, identical input, completely dissimilar strings
  - Mock dependencies: None (pure algorithm)
  - Assertions focus: `expect().to include()`, `expect().to be_empty`

- `bundler/spec/bundler/lockfile_generator_spec.rb` — Lockfile generation
  - Test categories: header generation, GEM section formatting, PLATFORMS section, DEPENDENCIES section, BUNDLED WITH section, empty dependency list
  - Mock dependencies: Stubbed `Bundler::Definition` with controlled dependency data
  - Assertions focus: `expect().to include()`, `expect().to match()` on generated string content

- `bundler/spec/bundler/uri_normalizer_spec.rb` — URI normalization
  - Test categories: trailing slash removal, scheme normalization, credential preservation, empty URI handling, special characters
  - Mock dependencies: None (pure string transformation)
  - Assertions focus: `expect().to eq()` on normalized URI strings

- `bundler/spec/bundler/process_lock_spec.rb` — File-based locking
  - Test categories: lock acquisition, block execution, lock release on success, lock release on exception, file permission handling
  - Mock dependencies: Temporary file system paths
  - Assertions focus: `expect().to yield_control`, file existence checks

### 0.5.3 Test Files to Modify Detail

- `test/rubygems/test_gem_specification.rb` — Add 3-5 test cases for SpecificationPolicy validation
  - New test methods: `test_specification_validates_via_policy`, `test_specification_policy_warnings`, `test_specification_policy_strict_mode`
  - Updated fixtures: Add invalid gemspec attributes that trigger policy validation errors
  - Assertions to add: `assert_raises Gem::InvalidSpecificationException` for policy violations

- `test/rubygems/test_gem_installer.rb` — Add 2-3 test cases for plugin regeneration
  - New test methods: `test_installer_regenerates_plugins`, `test_installer_handles_missing_plugins_dir`
  - Updated fixtures: Add gem fixture with plugin files
  - Assertions to add: `assert File.exist?` for regenerated plugin files

- `test/rubygems/test_gem_safe_marshal.rb` — Add 3-4 edge case tests
  - New test methods: `test_safe_marshal_with_psych_tree_encoding`, `test_safe_marshal_complex_nested_yaml`
  - Updated fixtures: Add YAML strings with Unicode and encoding variations
  - Assertions to add: `assert_equal` on deserialized structure

- `bundler/spec/bundler/definition_spec.rb` — Add LockfileGenerator integration
  - New test contexts: `context "when generating lockfile"` with 2-3 examples
  - Updated fixtures: Mock definition with controlled specs
  - Assertions to add: `expect(lockfile_content).to include()` for generated sections

- `bundler/spec/bundler/yaml_serializer_spec.rb` — Extend edge cases
  - New test contexts: `context "with special characters"`, `context "with empty input"`, `context "with malformed YAML"`
  - Assertions to add: Round-trip equality, error handling for malformed input

### 0.5.4 Test Configuration Updates

- `Rakefile` — No changes required; existing `test` and `test:isolated` tasks already discover `test/rubygems/test_gem_*.rb` via glob pattern
- `.github/workflows/rubygems.yml` — No changes required; CI already runs all tests matching the glob pattern
- `.github/workflows/bundler.yml` — No changes required; RSpec discovers all `*_spec.rb` files in `bundler/spec/`
- `.rubocop.yml` — No changes required; test files are already included in the linting scope

### 0.5.5 Cross-File Test Dependencies

**Shared Fixtures:**
- `test/rubygems/helper.rb` — Required by all RubyGems test files; provides `Gem::TestCase` base class with `setup`/`teardown`, temporary directory management, and credential helpers
- `test/rubygems/utilities.rb` — Provides `Gem::FakeFetcher` and `Gem::MockGemUi`; required by tests needing network or UI mocking
- `bundler/spec/spec_helper.rb` — Required by all Bundler spec files; configures RSpec and loads shared support modules
- `bundler/spec/support/helpers.rb` — Provides common Bundler test helper methods

**Mock Objects:**
- `Gem::FakeFetcher` (from `test/rubygems/utilities.rb`) — Used by `test_gem_s3_uri_signer.rb`, `test_gem_commands_generate_index_command.rb`
- `Gem::MockGemUi` (from `test/rubygems/utilities.rb`) — Used by all command tests and `test_gem_user_interaction.rb`
- RSpec doubles — Used in Bundler specs for external service isolation

**Test Utilities:**
- `Gem::TestCase#util_spec` — Helper for constructing `Gem::Specification` instances in tests
- `Gem::TestCase#install_gem` — Helper for installing gems in the test gem home
- `Gem::TestCase#quick_gem` — Quick gem creation for test setup

**Import Updates Required:**
- All new RubyGems test files: `require_relative "helper"` (standard)
- All new Bundler spec files: `require "spec_helper"` (standard)
- No import transformation rules needed — all new files follow existing conventions


## 0.6 Dependency Inventory

### 0.6.1 Testing Dependencies

All packages below use the EXACT names and versions from the repository's dependency manifest files (`tool/bundler/dev_gems.rb`, `tool/bundler/test_gems.rb`, and `rubygems-update.gemspec`).

| Registry | Package Name | Version | Purpose |
|---|---|---|---|
| rubygems | test-unit | ~> 3.0 | Primary testing framework for RubyGems test suite (Test::Unit) |
| rubygems | rspec-core | ~> 3.12 | BDD testing framework for Bundler spec suite |
| rubygems | rspec-expectations | ~> 3.12 | Matcher library for RSpec assertions |
| rubygems | rspec-mocks | ~> 3.12 | Test double library for RSpec (external dependency mocking only) |
| rubygems | turbo_tests | ~> 2.2.3 | Parallel test runner for Bundler specs |
| rubygems | parallel_tests | ~> 4.10.1 | Multi-process test execution |
| rubygems | parallel | ~> 1.19 | Parallel execution utility library |
| rubygems | rake | ~> 13.1 | Build and test task automation |
| rubygems | rack | ~> 3.1 | HTTP testing infrastructure (test servers) |
| rubygems | rack-test | ~> 2.1 | HTTP request testing utilities |
| rubygems | sinatra | ~> 4.1 | Test HTTP server framework |
| rubygems | compact_index | ~> 0.15.0 | Compact index format testing (Bundler integration) |
| rubygems | power_assert | >= 0 | Transitive dependency of test-unit |
| system | ruby | >= 3.2.0 | Runtime (tested on 3.2.x, 3.3.x, 3.4.x) |

### 0.6.2 Import Updates

**Import Patterns for New RubyGems Test Files:**

All new test files under `test/rubygems/` follow the standard import pattern:

```ruby
require_relative "helper"
# Production module loaded automatically via helper

```

- `test/rubygems/helper.rb` configures the load path (`-Ilib:test`) and loads `rubygems` core, making all `Gem::*` classes available without explicit `require` statements for most modules
- Specific modules that are autoloaded or lazily loaded may require explicit `require "rubygems/<module>"` at the top of their test file

**Import Patterns for New Bundler Spec Files:**

All new spec files under `bundler/spec/bundler/` follow the standard import pattern:

```ruby
require "spec_helper"
# Production module loaded via Bundler autoload

```

- `bundler/spec/spec_helper.rb` configures RSpec and loads the Bundler library, making `Bundler::*` classes available
- Specs for modules not autoloaded by Bundler may need explicit `require "bundler/<module>"` statements

**No Import Transformation Rules Required:**
- All new files are additive — no existing import paths change
- No module renames or path restructuring is involved
- The `require_relative "helper"` / `require "spec_helper"` pattern is universal across all test/spec files in the repository


## 0.7 Coverage and Quality Targets

### 0.7.1 Coverage Metrics

**Current Coverage (Estimated from Gap Analysis):**

| Component | Source Files | Test/Spec Files | Estimated Coverage | Gap |
|---|---|---|---|---|
| RubyGems root modules (`lib/rubygems/*.rb`) | 71 | 49 (dedicated) | ~69% file coverage | 22 files without dedicated tests |
| RubyGems commands (`lib/rubygems/commands/`) | ~30 | ~27 | ~90% file coverage | 3 commands without tests |
| RubyGems resolver (`lib/rubygems/resolver/`) | 25 | 20 | ~80% file coverage | 5 modules without tests |
| Bundler core (`bundler/lib/bundler/*.rb`) | 75 | 35 | ~47% file coverage | 40 files without specs (excluding vendored shims) |

**Target Coverage After Implementation:**

| Component | Current Files Covered | New Files to Add | Target Coverage |
|---|---|---|---|
| RubyGems root modules | 49/71 | +17 new test files | 66/71 (93%) |
| RubyGems commands | 27/30 | +2 new test files | 29/30 (97%) |
| RubyGems resolver | 20/25 | +5 new test files | 25/25 (100%) |
| Bundler core (non-vendored) | 35/75 | +25 new spec files | 60/75 (80%) |

**Coverage Gaps to Address (Priority Order):**

- `Gem::SpecificationPolicy` (558 lines): Currently 0% dedicated coverage, target 85%+ method coverage — validation is the most critical public API
- `Gem::UserInteraction` (650 lines): Currently 0% dedicated coverage (partially tested via `StreamUI`), target 70%+ method coverage — I/O helpers are user-facing
- `Bundler::Resolver` (524 lines): Currently 0% dedicated spec coverage, target 75%+ method coverage — resolution correctness is critical
- `Bundler::RubygemsExt` (481 lines): Currently 0% dedicated spec coverage, target 70%+ method coverage — monkey-patches are high-risk
- `Gem::BasicSpecification` (393 lines): Currently 0% dedicated coverage, target 80%+ method coverage — base class contract
- `Gem::QueryUtils` (349 lines): Currently 0% dedicated coverage, target 75%+ method coverage — CLI user-facing output
- `Bundler::Runtime` (320 lines): Currently 0% dedicated spec coverage, target 70%+ method coverage — gem activation is critical
- `Gem::Defaults` (308 lines): Currently 0% dedicated coverage, target 80%+ method coverage — path defaults affect entire system
- `Bundler::Injector` (285 lines): Currently 0% dedicated spec coverage, target 75%+ method coverage
- `Bundler::Errors` (277 lines): Currently 0% dedicated spec coverage, target 90%+ class coverage — error hierarchy completeness
- `Bundler::Checksum` (270 lines): Currently 0% dedicated spec coverage, target 85%+ method coverage — security-related
- Focus areas across all modules: critical paths (happy path + most common error), error handlers (exception classes and messages), edge cases (nil inputs, empty collections, boundary values)

### 0.7.2 Test Quality Criteria

**Assertion Density Expectations:**
- Minimum 2 assertions per test method (RubyGems) / per `it` block (Bundler)
- High-value test methods should contain 3-5 focused assertions validating different aspects of a single production method call
- Every test must assert on a production code return value or observable side effect — no assertion-free tests

**Test Isolation Requirements:**
- Each test method must be independently runnable without dependency on other test methods
- `setup`/`teardown` (Test::Unit) or `before`/`after` (RSpec) must fully initialize and clean up state
- No shared mutable state between test methods
- External dependencies (network, file system) must be isolated via the repository's established mocking infrastructure

**Performance Constraints:**
- Individual test files should execute in under 5 seconds for unit tests
- No sleep statements or artificial delays in unit tests
- Network mocking via `Gem::FakeFetcher` or `Artifice` must be synchronous (no real HTTP)

**Maintainability Standards:**
- Test method names must clearly describe the scenario: `test_<method>_<scenario>` for Test::Unit, `it "<description>"` for RSpec
- Complex setup logic should be extracted to helper methods rather than duplicated across tests
- Test data should be minimal — include only the attributes necessary for the specific test scenario
- Follow DRY principle within test files while maintaining test independence

**Repository Convention Compliance:**
- RubyGems tests: Inherit `Gem::TestCase`, use `assert_*` methods, follow `test_<class>_<method>` naming
- Bundler specs: Use `RSpec.describe`, organize with `context` blocks, use `let` for lazy-evaluated fixtures
- All tests must pass `rubocop` linting without exceptions
- No `skip` or `pending` markers on new tests — all tests must be fully implemented and passing


## 0.8 Scope Boundaries

### 0.8.1 Exhaustively In Scope

**New Test Files (RubyGems — Test::Unit):**
- `test/rubygems/test_gem_specification_policy.rb`
- `test/rubygems/test_gem_basic_specification.rb`
- `test/rubygems/test_gem_query_utils.rb`
- `test/rubygems/test_gem_defaults.rb`
- `test/rubygems/test_gem_exceptions.rb`
- `test/rubygems/test_gem_s3_uri_signer.rb`
- `test/rubygems/test_gem_specification_record.rb`
- `test/rubygems/test_gem_errors.rb`
- `test/rubygems/test_gem_deprecate.rb`
- `test/rubygems/test_gem_yaml_serializer.rb`
- `test/rubygems/test_gem_user_interaction.rb`
- `test/rubygems/test_gem_target_rbconfig.rb`
- `test/rubygems/test_gem_security_option.rb`
- `test/rubygems/test_gem_psych_tree.rb`
- `test/rubygems/test_gem_installer_uninstaller_utils.rb`
- `test/rubygems/test_gem_unknown_command_spell_checker.rb`
- `test/rubygems/test_gem_gemspec_helpers.rb`
- `test/rubygems/test_gem_commands_generate_index_command.rb`
- `test/rubygems/test_gem_commands_rdoc_command.rb`
- `test/rubygems/test_gem_resolver_set.rb`
- `test/rubygems/test_gem_resolver_current_set.rb`
- `test/rubygems/test_gem_resolver_source_set.rb`
- `test/rubygems/test_gem_resolver_spec_specification.rb`
- `test/rubygems/test_gem_resolver_stats.rb`

**New Test Files (Bundler — RSpec):**
- `bundler/spec/bundler/resolver_spec.rb`
- `bundler/spec/bundler/rubygems_ext_spec.rb`
- `bundler/spec/bundler/runtime_spec.rb`
- `bundler/spec/bundler/injector_spec.rb`
- `bundler/spec/bundler/errors_spec.rb`
- `bundler/spec/bundler/checksum_spec.rb`
- `bundler/spec/bundler/lazy_specification_spec.rb`
- `bundler/spec/bundler/installer_spec.rb`
- `bundler/spec/bundler/self_manager_spec.rb`
- `bundler/spec/bundler/rubygems_gem_installer_spec.rb`
- `bundler/spec/bundler/lockfile_generator_spec.rb`
- `bundler/spec/bundler/inline_spec.rb`
- `bundler/spec/bundler/compact_index_client_spec.rb`
- `bundler/spec/bundler/source_map_spec.rb`
- `bundler/spec/bundler/similarity_detector_spec.rb`
- `bundler/spec/bundler/materialization_spec.rb`
- `bundler/spec/bundler/deprecate_spec.rb`
- `bundler/spec/bundler/match_platform_spec.rb`
- `bundler/spec/bundler/safe_marshal_spec.rb`
- `bundler/spec/bundler/match_metadata_spec.rb`
- `bundler/spec/bundler/match_remote_metadata_spec.rb`
- `bundler/spec/bundler/uri_normalizer_spec.rb`
- `bundler/spec/bundler/process_lock_spec.rb`
- `bundler/spec/bundler/feature_flag_spec.rb`
- `bundler/spec/bundler/force_platform_spec.rb`

**Existing Test File Updates:**
- `test/rubygems/test_gem_specification.rb` — Add SpecificationPolicy integration paths
- `test/rubygems/test_gem_installer.rb` — Add plugin regeneration paths
- `test/rubygems/test_gem_safe_marshal.rb` — Add PsychTree edge cases
- `test/rubygems/test_gem_commands_mirror.rb` — Verify and extend MirrorCommand coverage
- `test/rubygems/test_gem_stream_ui.rb` — Extend UserInteraction method coverage
- `bundler/spec/bundler/definition_spec.rb` — Add LockfileGenerator path
- `bundler/spec/bundler/yaml_serializer_spec.rb` — Extend edge cases

**Test Infrastructure (Reference Only — No Modifications):**
- `test/rubygems/helper.rb`
- `test/rubygems/utilities.rb`
- `bundler/spec/spec_helper.rb`
- `bundler/spec/support/**/*.rb`

**Test Configuration (No Modifications Required):**
- `Rakefile` — Glob pattern already discovers new test files
- `.github/workflows/rubygems.yml` — CI already covers all test files
- `.github/workflows/bundler.yml` — CI already discovers all spec files

### 0.8.2 Explicitly Out of Scope

- **Source code modifications:** Production files under `lib/rubygems/` and `bundler/lib/bundler/` will NOT be modified. Tests must work with the existing production API as-is. If a production method is untestable without source changes, document the limitation rather than modifying source.
- **Vendored dependency testing:** Files matching `lib/rubygems/vendored_*.rb` and `bundler/lib/bundler/vendored_*.rb` are excluded — these are third-party libraries maintained upstream
- **Platform-specific shims:** `lib/rubygems/win_platform.rb` is excluded from dedicated testing (platform-specific behavior tested implicitly through CI matrix)
- **Trivial files:** Files under 10 lines that are pure require shims (e.g., `lib/rubygems/ext.rb` at 20 lines, `lib/rubygems/openssl.rb` at 7 lines, `lib/rubygems/install_default_message.rb` at 13 lines, `lib/rubygems/install_message.rb` at 13 lines) — these are delegation shims with no testable logic
- **Bundler vendored shims:** `bundler/lib/bundler/vendored_fileutils.rb`, `vendored_net_http.rb`, `vendored_persistent.rb`, `vendored_pub_grub.rb`, `vendored_securerandom.rb`, `vendored_thor.rb`, `vendored_timeout.rb`, `vendored_tsort.rb`, `vendored_uri.rb` — these are pure require redirects to vendored code
- **Bundler deployment adapters:** `bundler/lib/bundler/capistrano.rb` (4 lines), `bundler/lib/bundler/deployment.rb` (6 lines), `bundler/lib/bundler/vlad.rb` (4 lines), `bundler/lib/bundler/gem_tasks.rb` (7 lines) — deprecated or trivial Rake task loaders
- **Bundler setup shim:** `bundler/lib/bundler/setup.rb` (39 lines) — bootstrapping shim tested through integration flows
- **Bundler version constant:** `bundler/lib/bundler/version.rb` (21 lines) — single constant definition, no testable logic
- **Bundler constants:** `bundler/lib/bundler/constants.rb` (14 lines) — constant definitions only
- **Refactoring beyond test needs:** No production code restructuring, method extraction, or API changes
- **Feature additions:** No new production functionality while adding tests
- **Unrelated test files:** Tests for modules not identified in the gap analysis
- **Performance optimizations:** No production performance work; test execution performance is the only performance concern
- **Documentation files:** No changes to `README.md`, man pages, or API documentation


## 0.9 Execution Parameters

### 0.9.1 Testing-Specific Instructions

**Test Execution Commands:**

- **Run all RubyGems tests:**
  ```
  cd /tmp/blitzy/blitzy-rubygems/master && timeout 600 ruby -Ilib:test -e "Dir.glob('test/rubygems/test_gem_*.rb').each { |f| require_relative f }"
  ```

- **Run a single RubyGems test file:**
  ```
  timeout 60 ruby -Ilib:test test/rubygems/test_gem_specification_policy.rb
  ```

- **Run all RubyGems tests via Rake:**
  ```
  timeout 600 rake test
  ```

- **Run RubyGems tests in isolation mode:**
  ```
  timeout 900 rake test:isolated
  ```

- **Run all Bundler specs:**
  ```
  cd bundler && timeout 600 bin/rspec spec/bundler/
  ```

- **Run a single Bundler spec file:**
  ```
  timeout 60 bin/rspec spec/bundler/checksum_spec.rb
  ```

- **Run Bundler specs in parallel:**
  ```
  cd bundler && timeout 600 bin/turbo_tests spec/bundler/
  ```

**Debug Mode Execution:**

- **RubyGems (verbose with backtrace):**
  ```
  timeout 60 ruby -Ilib:test -d test/rubygems/test_gem_specification_policy.rb
  ```

- **Bundler (formatted output):**
  ```
  cd bundler && timeout 60 bin/rspec --format documentation spec/bundler/checksum_spec.rb
  ```

**Single Test Method Execution:**

- **RubyGems (run one method):**
  ```
  timeout 30 ruby -Ilib:test test/rubygems/test_gem_yaml_serializer.rb -n test_dump_simple_hash
  ```

- **Bundler (run one example):**
  ```
  cd bundler && timeout 30 bin/rspec spec/bundler/checksum_spec.rb:15
  ```

**Specific Test Patterns to Follow in the Repository:**

- RubyGems: Every test class inherits `Gem::TestCase`, uses `setup` for fixture initialization, and invokes production code directly with `assert_*` validation
- Bundler: Every spec uses `RSpec.describe Bundler::<Module>`, organizes with `context` blocks per scenario, and uses `let`/`before` for lazy fixture initialization
- All mock usage restricted to `Gem::FakeFetcher`/`Gem::MockGemUi` (RubyGems) or RSpec doubles for external services (Bundler)

**Excluded Test Categories:**
- End-to-end system tests (run separately in CI)
- Performance benchmarks
- Security audit tests (handled by `zizmor` and `codespell` in CI)

**Environment Setup Requirements for Tests:**

- Ruby >= 3.2.0 installed and in PATH
- `test-unit` gem installed (`gem install test-unit`)
- `rspec-core`, `rspec-expectations`, `rspec-mocks` gems installed for Bundler specs
- Working directory set to repository root for RubyGems tests, `bundler/` for Bundler specs
- No external services required — all external dependencies are mocked
- No database setup required — file-system-based storage with temporary directories


## 0.10 Special Instructions for Testing

### 0.10.1 Testing-Specific Requirements Explicitly Emphasized by the User

The following directives are drawn directly from the user's requirements and must be treated as inviolable constraints throughout test implementation:

**Zero Business Logic in Tests (MANDATORY):**
- "Each test file must contain zero lines of business logic implementation. Any test containing reimplemented business logic or duplicated algorithms fails review automatically."
- Every test file must be auditable against this gate. A test file passes if and only if every line belongs to one of four categories: (1) import/require statements, (2) test setup/fixture initialization, (3) production function invocation, (4) assertion statements.
- No line in any test file may contain a reimplemented algorithm, calculation, data transformation, or conditional logic that duplicates what the production code does.

**Direct Production Code Invocation (MANDATORY):**
- "Import production functions, methods, and classes directly from source modules"
- All tests must `require` the production module and call its methods on real instances. Example: `Gem::SpecificationPolicy.new(spec).validate` — not a test-local re-creation of the validation logic.
- "Tests must invoke real production functions, not reimplement business logic"

**Forbidden Patterns (MANDATORY — verbatim from user):**
- "Copying function logic into test files" — No test may contain code that mirrors the internal implementation of a production method
- "Creating test-local implementations that duplicate production behavior" — No helper methods in tests that reproduce what production code does
- "Mocking internal functions under test" — The method being tested must never be stubbed, mocked, or replaced. Only external dependencies (network, file I/O, external services) may be mocked.

**Mocking Boundary Enforcement:**
- Mock or stub ONLY external dependencies: HTTP requests (via `Gem::FakeFetcher`), file system operations (via `Gem::TestCase` temp dirs), external service responses (via RSpec doubles)
- NEVER mock, stub, or replace: the production class under test, its internal methods, its internal collaborators within the same module, or any method whose behavior is the subject of the test assertion

**Test Structure Enforcement:**
- "Test structure must contain only: imports, test setup/fixtures, function invocation, and assertions"
- "Test assertions must validate return values and side effects of actual production code execution"
- Each test method follows the strict Arrange-Act-Assert pattern:
  - **Arrange:** Set up inputs, fixtures, and mocked external dependencies
  - **Act:** Call the real production method with the arranged inputs
  - **Assert:** Validate the return value, raised exceptions, or observable side effects

**Validation Gate Implementation:**
- Before any test file is considered complete, it must be verifiable that it contains zero lines of duplicated business logic
- A review heuristic: if a test file contains conditional logic (`if`/`else`/`case`), arithmetic operations, string manipulations, or data transformations that mirror production code, it fails the gate
- Acceptable test-only logic: constructing input fixtures (hardcoded values), selecting which assertion to use, and iterating over known expected values for parameterized tests

**Convention Compliance:**
- Match existing code style and naming conventions: `TestGem<Module> < Gem::TestCase` for RubyGems, `RSpec.describe Bundler::<Module>` for Bundler
- Follow the established test organization patterns observed in the repository's existing 136 RubyGems test files and 35 Bundler spec files
- All tests must run independently and pass in isolation (verified via `rake test:isolated`)


