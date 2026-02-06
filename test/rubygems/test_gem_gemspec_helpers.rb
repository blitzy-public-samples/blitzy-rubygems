# frozen_string_literal: true

require_relative "helper"
require "rubygems/gemspec_helpers"

class TestGemGemspecHelpers < Gem::TestCase
  # Include GemspecHelpers to directly invoke find_gemspec on the test instance.
  # Include UserInteraction to provide alert_error and terminate_interaction
  # methods that GemspecHelpers#find_gemspec depends on when multiple gemspecs
  # are found in the directory.
  include Gem::GemspecHelpers
  include Gem::UserInteraction

  ##
  # Tests that find_gemspec returns the filename when exactly one .gemspec
  # file exists in the directory.

  def test_find_gemspec_single_file
    dir = File.join(@tempdir, "single_gemspec")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "test.gemspec"), "")

    result = Dir.chdir(dir) { find_gemspec }

    assert_equal "test.gemspec", result
    assert_kind_of String, result
  end

  ##
  # Tests that find_gemspec returns nil when the directory contains no
  # .gemspec files, including when non-gemspec files are present.

  def test_find_gemspec_no_files
    dir = File.join(@tempdir, "no_gemspec")
    FileUtils.mkdir_p(dir)

    result = Dir.chdir(dir) { find_gemspec }
    assert_nil result

    # Non-gemspec files should not be matched by the default glob
    File.write(File.join(dir, "readme.txt"), "")
    result_with_non_gemspec = Dir.chdir(dir) { find_gemspec }
    assert_nil result_with_non_gemspec
  end

  ##
  # Tests that find_gemspec raises a TermError (via terminate_interaction)
  # and emits an alert_error message when multiple .gemspec files are found.

  def test_find_gemspec_multiple_files
    dir = File.join(@tempdir, "multi_gemspec")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "a.gemspec"), "")
    File.write(File.join(dir, "b.gemspec"), "")

    use_ui @ui do
      Dir.chdir(dir) do
        assert_raise Gem::MockGemUi::TermError do
          find_gemspec
        end
      end
    end

    assert_match(/Multiple gemspecs found/, @ui.error)
  end

  ##
  # Tests that find_gemspec accepts a custom glob pattern and returns the
  # matching file while ignoring non-matching files.

  def test_find_gemspec_custom_glob
    dir = File.join(@tempdir, "custom_glob")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "custom.gemspec"), "")
    File.write(File.join(dir, "other.txt"), "")

    result = Dir.chdir(dir) { find_gemspec("custom.*") }

    assert_equal "custom.gemspec", result
    assert_kind_of String, result
  end

  ##
  # Tests that find_gemspec returns the first sorted match and that the
  # method is accessible when the module is included.

  def test_find_gemspec_returns_first_sorted
    dir = File.join(@tempdir, "sorted_gemspec")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "zebra.gemspec"), "")

    result = Dir.chdir(dir) { find_gemspec }

    assert_respond_to self, :find_gemspec
    assert_equal "zebra.gemspec", result
  end
end
