# frozen_string_literal: true

require "spec_helper"
require "bundler/process_lock"
require "tmpdir"

RSpec.describe Bundler::ProcessLock do
  describe ".lock" do
    it "is a class method that accepts a bundle_path and a block" do
      expect(described_class).to respond_to(:lock)
      expect(described_class.method(:lock).arity).to eq(-1)
    end

    it "yields to the provided block and returns its result" do
      Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
        block_executed = false
        result = described_class.lock(tmpdir) do
          block_executed = true
          :lock_return_value
        end
        expect(block_executed).to eq(true)
        expect(result).to eq(:lock_return_value)
      end
    end

    context "lock acquisition" do
      it "passes the bundle_path/bundler.lock path to filesystem_access for write" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          expected_lock_path = File.join(tmpdir, "bundler.lock")
          lock_path_seen = nil

          allow(Bundler::SharedHelpers).to receive(:filesystem_access).and_wrap_original do |original, path, action, &blk|
            lock_path_seen = path
            original.call(path, action, &blk)
          end

          described_class.lock(tmpdir) { "acquired" }
          expect(lock_path_seen).to eq(expected_lock_path)
          expect(lock_path_seen).to end_with("bundler.lock")
        end
      end

      it "delegates to Gem.open_file_with_lock with the base path (without .lock suffix)" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          base_path_seen = nil

          allow(Gem).to receive(:open_file_with_lock).and_wrap_original do |original, path, &blk|
            base_path_seen = path
            original.call(path, &blk)
          end

          described_class.lock(tmpdir) { "test" }

          expected_base = File.join(tmpdir, "bundler")
          expect(base_path_seen).to eq(expected_base)
          expect(base_path_seen).not_to end_with(".lock")
        end
      end

      it "creates the lock file on disk during block execution" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_file = File.join(tmpdir, "bundler.lock")
          lock_existed_during_block = false

          described_class.lock(tmpdir) do
            lock_existed_during_block = File.exist?(lock_file)
          end

          expect(lock_existed_during_block).to eq(true)
          expect(File.exist?(lock_file)).to eq(false)
        end
      end
    end

    context "block execution" do
      it "executes the provided block exactly once" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          execution_count = 0
          described_class.lock(tmpdir) do
            execution_count += 1
          end
          expect(execution_count).to eq(1)
          expect(execution_count).to be > 0
        end
      end

      it "executes the block within the lock scope in correct order" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          call_order = []
          call_order << :before_lock
          described_class.lock(tmpdir) do
            call_order << :inside_lock
          end
          call_order << :after_lock

          expect(call_order).to eq([:before_lock, :inside_lock, :after_lock])
          expect(call_order.length).to eq(3)
        end
      end

      it "propagates the return value of the block" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          result = described_class.lock(tmpdir) { { key: "value", count: 42 } }
          expect(result).to be_a(Hash)
          expect(result).to eq({ key: "value", count: 42 })
        end
      end
    end

    context "release on success" do
      it "removes the lock file after the block completes successfully" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_file = File.join(tmpdir, "bundler.lock")

          described_class.lock(tmpdir) { "success" }

          expect(File.exist?(lock_file)).to eq(false)
          expect(Dir.children(tmpdir)).not_to include("bundler.lock")
        end
      end

      it "returns the block value and cleans up the lock file" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_file = File.join(tmpdir, "bundler.lock")

          result = described_class.lock(tmpdir) { :completed_value }

          expect(result).to eq(:completed_value)
          expect(File.exist?(lock_file)).to eq(false)
        end
      end
    end

    context "release on exception" do
      it "propagates the exception and cleans up the lock file" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_file = File.join(tmpdir, "bundler.lock")

          expect {
            described_class.lock(tmpdir) { raise ArgumentError, "test error inside lock" }
          }.to raise_error(ArgumentError, "test error inside lock")

          expect(File.exist?(lock_file)).to eq(false)
        end
      end

      it "cleans up the lock file after a RuntimeError in the block" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_file = File.join(tmpdir, "bundler.lock")

          begin
            described_class.lock(tmpdir) { raise RuntimeError, "runtime failure" }
          rescue RuntimeError
            # expected — exception is caught to allow assertions below
          end

          expect(File.exist?(lock_file)).to eq(false)
          expect(Dir.children(tmpdir)).not_to include("bundler.lock")
        end
      end

      it "cleans up the lock file after a StandardError subclass in the block" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_file = File.join(tmpdir, "bundler.lock")

          begin
            described_class.lock(tmpdir) { raise IOError, "io failure in lock" }
          rescue IOError
            # expected
          end

          expect(File.exist?(lock_file)).to eq(false)
          expect(Dir.children(tmpdir)).not_to include("bundler.lock")
        end
      end
    end

    context "file permission handling" do
      it "falls back to calling the block directly when PermissionError is raised" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_path = File.join(tmpdir, "bundler.lock")

          allow(Bundler::SharedHelpers).to receive(:filesystem_access)
            .with(lock_path, :write)
            .and_raise(Bundler::PermissionError.new(lock_path, :write))

          block_executed = false
          result = described_class.lock(tmpdir) do
            block_executed = true
            :fallback_value
          end

          expect(block_executed).to eq(true)
          expect(result).to eq(:fallback_value)
        end
      end

      it "does not propagate the PermissionError to the caller" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_path = File.join(tmpdir, "bundler.lock")

          allow(Bundler::SharedHelpers).to receive(:filesystem_access)
            .with(lock_path, :write)
            .and_raise(Bundler::PermissionError.new(lock_path, :write))

          expect {
            described_class.lock(tmpdir) { "ok" }
          }.not_to raise_error

          expect(Bundler::SharedHelpers).to have_received(:filesystem_access).with(lock_path, :write)
        end
      end

      it "still returns the block value on PermissionError fallback" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_path = File.join(tmpdir, "bundler.lock")

          allow(Bundler::SharedHelpers).to receive(:filesystem_access)
            .with(lock_path, :write)
            .and_raise(Bundler::PermissionError.new(lock_path, :write))

          result = described_class.lock(tmpdir) { "permission_fallback_result" }
          expect(result).to eq("permission_fallback_result")
          expect(Bundler::SharedHelpers).to have_received(:filesystem_access).once
        end
      end
    end

    context "with default bundle_path" do
      it "defaults to Bundler.bundle_path when no argument is given" do
        default_path = Dir.mktmpdir("bundler_default_test")
        allow(Bundler).to receive(:bundle_path).and_return(Pathname.new(default_path))

        block_called = false
        described_class.lock do
          block_called = true
        end

        expect(block_called).to eq(true)
        expect(Bundler).to have_received(:bundle_path)
      ensure
        FileUtils.rm_rf(default_path) if default_path
      end
    end

    context "with paths containing spaces" do
      it "handles bundle_path with spaces correctly" do
        Dir.mktmpdir("bundler lock test spaces") do |tmpdir|
          result = described_class.lock(tmpdir) { :spaced_path_result }
          lock_file = File.join(tmpdir, "bundler.lock")
          expect(result).to eq(:spaced_path_result)
          expect(File.exist?(lock_file)).to eq(false)
        end
      end
    end
  end
end
