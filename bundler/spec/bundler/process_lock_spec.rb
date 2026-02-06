# frozen_string_literal: true

require "spec_helper"
require "bundler/process_lock"
require "tmpdir"

RSpec.describe Bundler::ProcessLock do
  describe ".lock" do
    context "when lock acquisition succeeds" do
      it "yields control to the provided block" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          block_executed = false
          Bundler::ProcessLock.lock(tmpdir) do
            block_executed = true
          end
          expect(block_executed).to eq(true)
        end
      end

      it "returns the value from the block" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          result = Bundler::ProcessLock.lock(tmpdir) { :lock_result }
          expect(result).to eq(:lock_result)
        end
      end

      it "computes the lock file path under the given bundle_path" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          expected_lock_path = File.join(tmpdir, "bundler.lock")
          lock_path_seen = nil

          allow(Bundler::SharedHelpers).to receive(:filesystem_access).and_wrap_original do |original, path, action, &blk|
            lock_path_seen = path
            original.call(path, action, &blk)
          end

          Bundler::ProcessLock.lock(tmpdir) { "done" }
          expect(lock_path_seen).to eq(expected_lock_path)
        end
      end

      it "passes the block through to Gem.open_file_with_lock" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          call_order = []
          Bundler::ProcessLock.lock(tmpdir) do
            call_order << :block_called
          end
          expect(call_order).to eq([:block_called])
        end
      end

      it "executes the block exactly once" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          execution_count = 0
          Bundler::ProcessLock.lock(tmpdir) do
            execution_count += 1
          end
          expect(execution_count).to eq(1)
        end
      end
    end

    context "when a PermissionError is raised during filesystem access" do
      it "falls back to calling the block directly without the lock" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_path = File.join(tmpdir, "bundler.lock")

          allow(Bundler::SharedHelpers).to receive(:filesystem_access).with(lock_path, :write).and_raise(
            Bundler::PermissionError.new(lock_path, :write)
          )

          block_executed = false
          Bundler::ProcessLock.lock(tmpdir) do
            block_executed = true
          end

          expect(block_executed).to eq(true)
        end
      end

      it "returns the block's return value on permission error fallback" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_path = File.join(tmpdir, "bundler.lock")

          allow(Bundler::SharedHelpers).to receive(:filesystem_access).with(lock_path, :write).and_raise(
            Bundler::PermissionError.new(lock_path, :write)
          )

          result = Bundler::ProcessLock.lock(tmpdir) { :fallback_result }
          expect(result).to eq(:fallback_result)
        end
      end

      it "does not re-raise the PermissionError" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          lock_path = File.join(tmpdir, "bundler.lock")

          allow(Bundler::SharedHelpers).to receive(:filesystem_access).with(lock_path, :write).and_raise(
            Bundler::PermissionError.new(lock_path, :write)
          )

          expect {
            Bundler::ProcessLock.lock(tmpdir) { "ok" }
          }.not_to raise_error
        end
      end
    end

    context "with a custom bundle_path" do
      it "uses the custom path for the lock file" do
        Dir.mktmpdir("bundler_custom_path_test") do |custom_path|
          expected_lock = File.join(custom_path, "bundler.lock")
          received_path = nil

          allow(Bundler::SharedHelpers).to receive(:filesystem_access).and_wrap_original do |original, path, action, &blk|
            received_path = path
            original.call(path, action, &blk)
          end

          Bundler::ProcessLock.lock(custom_path) { "result" }
          expect(received_path).to eq(expected_lock)
        end
      end

      it "works with paths containing spaces" do
        Dir.mktmpdir("bundler lock test") do |tmpdir|
          result = Bundler::ProcessLock.lock(tmpdir) { :spaced_path_result }
          expect(result).to eq(:spaced_path_result)
        end
      end
    end

    context "when the block raises an exception" do
      it "propagates the exception from within the lock" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          expect {
            Bundler::ProcessLock.lock(tmpdir) { raise ArgumentError, "test error" }
          }.to raise_error(ArgumentError, "test error")
        end
      end

      it "propagates RuntimeError from within the lock" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          expect {
            Bundler::ProcessLock.lock(tmpdir) { raise RuntimeError, "runtime failure" }
          }.to raise_error(RuntimeError, "runtime failure")
        end
      end
    end

    context "when called with default arguments" do
      it "uses Bundler.bundle_path as the default path" do
        expect(Bundler).to receive(:bundle_path).and_return(Pathname.new(Dir.mktmpdir("bundler_default_test")))

        block_called = false
        Bundler::ProcessLock.lock do
          block_called = true
        end
        expect(block_called).to eq(true)
      end
    end

    describe "lock file path computation" do
      it "derives the base lock file path by removing .lock suffix from bundler.lock" do
        Dir.mktmpdir("bundler_process_lock_test") do |tmpdir|
          base_path_seen = nil

          allow(Gem).to receive(:open_file_with_lock).and_wrap_original do |original, path, &blk|
            base_path_seen = path
            original.call(path, &blk)
          end

          Bundler::ProcessLock.lock(tmpdir) { "test" }

          expected_base = File.join(tmpdir, "bundler")
          expect(base_path_seen).to eq(expected_base)
        end
      end
    end

    describe "class interface" do
      it "is a class method on ProcessLock" do
        expect(Bundler::ProcessLock).to respond_to(:lock)
      end

      it "accepts a block parameter" do
        expect(Bundler::ProcessLock.method(:lock).arity).to eq(-1)
      end
    end
  end
end
