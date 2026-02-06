# frozen_string_literal: true

require_relative "helper"
require "stringio"

class TestGemResolverStats < Gem::TestCase
  def setup
    super
    @stats = Gem::Resolver::Stats.new
  end

  # Verifies a freshly created Stats instance responds to all public methods
  # defined in the production class.
  def test_responds_to_all_methods
    assert_respond_to @stats, :record_depth
    assert_respond_to @stats, :record_requirements
    assert_respond_to @stats, :requirement!
    assert_respond_to @stats, :backtracking!
    assert_respond_to @stats, :iteration!
    assert_respond_to @stats, :display
  end

  # Verifies record_depth updates max_depth when given a stack whose size
  # exceeds the current maximum.
  def test_record_depth_updates_when_larger
    @stats.record_depth([1, 2, 3])

    output = capture_display

    assert_match(/Max Depth/, output)
    assert_match(/Max Depth: 3$/, output)
  end

  # Verifies record_depth retains the previous max_depth when a smaller stack
  # is recorded after a larger one.
  def test_record_depth_no_update_when_smaller
    @stats.record_depth([1, 2, 3, 4, 5])
    @stats.record_depth([1, 2])

    output = capture_display

    assert_match(/Max Depth: 5$/, output)
    refute_match(/Max Depth: 2$/, output)
  end

  # Verifies record_requirements updates max_requirements when given a
  # requirements collection whose size exceeds the current maximum.
  def test_record_requirements_updates_when_larger
    @stats.record_requirements([1, 2, 3, 4])

    output = capture_display

    assert_match(/Max Requirements/, output)
    assert_match(/Max Requirements: 4$/, output)
  end

  # Verifies record_requirements retains the previous max when a smaller
  # requirements collection is recorded after a larger one.
  def test_record_requirements_no_update_when_smaller
    @stats.record_requirements([1, 2, 3, 4, 5, 6])
    @stats.record_requirements([1])

    output = capture_display

    assert_match(/Max Requirements: 6$/, output)
    refute_match(/Max Requirements: 1$/, output)
  end

  # Verifies requirement! increments the total requirements counter each time
  # it is called.
  def test_requirement_bang_increments
    3.times { @stats.requirement! }

    output = capture_display

    assert_match(/Total Requirements/, output)
    assert_match(/Total Requirements: 3$/, output)
  end

  # Verifies backtracking! increments the backtracking counter each time
  # it is called.
  def test_backtracking_bang_increments
    4.times { @stats.backtracking! }

    output = capture_display

    assert_match(/Backtracking #/, output)
    assert_match(/Backtracking #: 4$/, output)
  end

  # Verifies iteration! increments the iterations counter each time
  # it is called.
  def test_iteration_bang_increments
    5.times { @stats.iteration! }

    output = capture_display

    assert_match(/Iteration #/, output)
    assert_match(/Iteration #: 5$/, output)
  end

  # Verifies the display method outputs the statistics header line.
  def test_display_header
    output = capture_display

    assert_match(/=== Resolver Statistics ===/, output)
    assert_includes output, "=== Resolver Statistics ==="
  end

  # Verifies display outputs the Max Depth line with the correct recorded value.
  def test_display_max_depth
    @stats.record_depth([1, 2, 3, 4, 5, 6, 7])

    output = capture_display

    assert_includes output, "Max Depth"
    assert_match(/Max Depth: 7$/, output)
  end

  # Verifies display outputs the Total Requirements line with the correct
  # accumulated count.
  def test_display_total_requirements
    10.times { @stats.requirement! }

    output = capture_display

    assert_includes output, "Total Requirements"
    assert_match(/Total Requirements: 10$/, output)
  end

  # Verifies display outputs the Max Requirements line with the correct
  # recorded maximum.
  def test_display_max_requirements
    @stats.record_requirements(Array.new(8))

    output = capture_display

    assert_includes output, "Max Requirements"
    assert_match(/Max Requirements: 8$/, output)
  end

  # Verifies display outputs the Backtracking # line with the correct count.
  def test_display_backtracking
    6.times { @stats.backtracking! }

    output = capture_display

    assert_includes output, "Backtracking #"
    assert_match(/Backtracking #: 6$/, output)
  end

  # Verifies display outputs the Iteration # line with the correct count.
  def test_display_iteration
    9.times { @stats.iteration! }

    output = capture_display

    assert_includes output, "Iteration #"
    assert_match(/Iteration #: 9$/, output)
  end

  # Verifies that a freshly created Stats instance displays all counters
  # as zero when no recording methods have been called.
  def test_display_zero_state
    output = capture_display

    assert_match(/Max Depth: 0$/, output)
    assert_match(/Total Requirements: 0$/, output)
    assert_match(/Max Requirements: 0$/, output)
    assert_match(/Backtracking #: 0$/, output)
    assert_match(/Iteration #: 0$/, output)
  end

  private

  # Captures $stdout output produced by Stats#display and returns it as a
  # String. Restores the original $stdout after capture to avoid polluting
  # other tests.
  def capture_display
    original_stdout = $stdout
    $stdout = StringIO.new
    @stats.display
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
