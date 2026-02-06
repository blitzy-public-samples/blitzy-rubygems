# frozen_string_literal: true

require "spec_helper"
require "bundler/inline"

# The gemfile method from bundler/inline is defined at the top-level (Object),
# but the Bundler test helpers (Spec::Helpers) define their own gemfile method
# for writing Gemfile contents to disk. We capture a reference to the real
# production gemfile method so we can invoke it directly, bypassing the test
# helper that shadows it.
INLINE_GEMFILE_METHOD = Object.instance_method(:gemfile)

RSpec.describe "Bundler inline gemfile" do
  # Invoke the real production gemfile method from bundler/inline, bypassing
  # the Spec::Helpers#gemfile test helper that shadows it on the receiver.
  def invoke_inline_gemfile(force_latest_compatible = false, options = {}, &block)
    INLINE_GEMFILE_METHOD.bind_call(self, force_latest_compatible, options, &block)
  end

  # Save and restore Bundler.ui around each example so stale mock references
  # do not leak into the spec_helper around(:each) hook that calls
  # Bundler.ui.silence { example.run }.
  around(:each) do |example|
    saved_ui = Bundler.ui
    example.run
  ensure
    Bundler.ui = saved_ui
  end

  # Stubs the full gemfile method flow so production code executes without
  # real side-effects (no real gem installation, no real network access, no
  # real file system mutations). Returns a hash of doubles for assertion use.
  #
  # @param missing_specs [Boolean] whether the definition reports missing specs
  # @param plugins_enabled [Boolean] whether the settings[:plugins] flag is on
  # @return [Hash] doubles keyed by :builder, :definition, :runtime, :installer, :settings
  def stub_gemfile_flow(missing_specs: false, plugins_enabled: false)
    builder   = instance_double(Bundler::Dsl)
    definition = double("Definition")
    runtime   = double("Runtime")
    installer = double("Installer", post_install_messages: {})
    settings  = double("Settings")

    # Bundler reset and environment isolation
    allow(Bundler).to receive(:reset!)
    allow(Bundler).to receive(:unbundle_env!)
    allow(Bundler).to receive(:instance_variable_set)
    allow(Bundler::SharedHelpers).to receive(:set_env)
    allow(Bundler).to receive(:root).and_return(Pathname.new("."))

    # Settings double — only :plugins key returns configurable boolean
    allow(settings).to receive(:[]) do |key|
      key == :plugins ? plugins_enabled : nil
    end
    allow(settings).to receive(:temporary).and_yield
    allow(Bundler).to receive(:settings).and_return(settings)

    # Plugin support (only stubbed when enabled to allow negative assertions)
    allow(Bundler::Plugin).to receive(:gemfile_install) if plugins_enabled

    # DSL builder and definition construction
    allow(Bundler::Dsl).to receive(:new).and_return(builder)
    allow(builder).to receive(:instance_eval)
    allow(builder).to receive(:to_definition).and_return(definition)
    allow(definition).to receive(:validate_runtime!)
    allow(definition).to receive(:missing_specs?).and_return(missing_specs)

    # Installer (returned when Bundler::Installer.install is invoked)
    allow(Bundler::Installer).to receive(:install).and_return(installer)

    # Runtime setup and require
    allow(Bundler::Runtime).to receive(:new).and_return(runtime)
    allow(runtime).to receive(:setup).and_return(runtime)
    allow(runtime).to receive(:require)

    {
      builder: builder,
      definition: definition,
      runtime: runtime,
      installer: installer,
      settings: settings,
    }
  end

  # Wraps invoke_inline_gemfile with BUNDLE_GEMFILE env-var protection so
  # the surrounding test environment is not permanently altered.
  def safe_invoke(force_latest_compatible = false, options = {}, &block)
    old = ENV["BUNDLE_GEMFILE"]
    invoke_inline_gemfile(force_latest_compatible, options, &block)
  ensure
    ENV["BUNDLE_GEMFILE"] = old || ""
  end

  # ------------------------------------------------------------------
  # gemfile method availability and signature
  # ------------------------------------------------------------------
  describe "gemfile method" do
    it "is defined on Object as an instance method and accepts variable arguments" do
      unbound = Object.instance_method(:gemfile)
      expect(unbound).to be_a(UnboundMethod)
      expect(unbound.arity).to eq(-1)
    end

    it "accepts force_latest_compatible, options hash, and a block parameter" do
      params = Object.instance_method(:gemfile).parameters
      expect(params).to include([:opt, :force_latest_compatible])
      expect(params).to include([:opt, :options])
      expect(params).to include([:block, :gemfile])
    end
  end

  # ------------------------------------------------------------------
  # inline dependency resolution
  # ------------------------------------------------------------------
  describe "inline dependency resolution" do
    it "invokes Bundler.reset! and Bundler.unbundle_env! to prepare environment" do
      stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler).to have_received(:reset!)
      expect(Bundler).to have_received(:unbundle_env!)
    end

    it "sets the bundle path to Gem.dir and configures BUNDLE_GEMFILE via SharedHelpers" do
      stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler).to have_received(:instance_variable_set)
        .with(:@bundle_path, Pathname.new(Gem.dir))
      expect(Bundler::SharedHelpers).to have_received(:set_env)
        .with("BUNDLE_GEMFILE", "Gemfile")
    end

    it "creates a Bundler::Dsl builder and evaluates the gemfile block on it" do
      doubles = stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Dsl).to have_received(:new)
      expect(doubles[:builder]).to have_received(:instance_eval)
    end

    it "converts builder to a definition with nil lockfile and unlock=true then validates" do
      doubles = stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(doubles[:builder]).to have_received(:to_definition).with(nil, true)
      expect(doubles[:definition]).to have_received(:validate_runtime!)
    end

    it "wraps resolution in temporary settings with deployment:false and frozen:false" do
      doubles = stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(doubles[:settings]).to have_received(:temporary)
        .with(deployment: false, frozen: false)
      expect(doubles[:definition]).to have_received(:validate_runtime!)
    end

    it "triggers installation when force_latest_compatible is true" do
      doubles = stub_gemfile_flow

      safe_invoke(true, { quiet: true }) { nil }

      expect(Bundler::Installer).to have_received(:install)
        .with(Pathname.new("."), anything, hash_including(system: true))
      expect(doubles[:runtime]).to have_received(:require)
    end

    it "triggers installation when definition reports missing specs" do
      doubles = stub_gemfile_flow(missing_specs: true)

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Installer).to have_received(:install)
      expect(doubles[:runtime]).to have_received(:require)
    end

    it "skips installation when not forced and no specs are missing" do
      doubles = stub_gemfile_flow(missing_specs: false)

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Installer).not_to have_received(:install)
      expect(doubles[:runtime]).to have_received(:require)
    end

    it "creates a Runtime with nil root and definition then calls setup" do
      doubles = stub_gemfile_flow

      allow(Bundler::Runtime).to receive(:new)
        .with(nil, doubles[:definition])
        .and_return(doubles[:runtime])

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Runtime).to have_received(:new).with(nil, doubles[:definition])
      expect(doubles[:runtime]).to have_received(:setup)
    end

    it "outputs post-install messages from the installer to Bundler.ui" do
      doubles = stub_gemfile_flow
      allow(doubles[:installer]).to receive(:post_install_messages)
        .and_return({ "mygem" => "Hello from mygem!" })

      custom_ui = Bundler::UI::Shell.new
      allow(custom_ui).to receive(:info).and_call_original

      safe_invoke(true, { ui: custom_ui }) { nil }

      expect(custom_ui).to have_received(:info)
        .with("Post-install message from mygem:\nHello from mygem!")
      expect(doubles[:runtime]).to have_received(:require)
    end
  end

  # ------------------------------------------------------------------
  # require behavior
  # ------------------------------------------------------------------
  describe "require behavior" do
    it "calls runtime.require after runtime.setup completes successfully" do
      doubles = stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(doubles[:runtime]).to have_received(:setup)
      expect(doubles[:runtime]).to have_received(:require)
    end

    it "calls runtime.require even when installation is skipped" do
      doubles = stub_gemfile_flow(missing_specs: false)

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Installer).not_to have_received(:install)
      expect(doubles[:runtime]).to have_received(:require)
    end

    it "calls runtime.require after installation when forced" do
      doubles = stub_gemfile_flow

      safe_invoke(true, { quiet: true }) { nil }

      expect(Bundler::Installer).to have_received(:install)
      expect(doubles[:runtime]).to have_received(:require)
    end
  end

  # ------------------------------------------------------------------
  # options handling
  # ------------------------------------------------------------------
  describe "options handling" do
    it "sets UI level to silent when :quiet option is true" do
      stub_gemfile_flow
      custom_ui = Bundler::UI::Shell.new

      safe_invoke(true, { ui: custom_ui, quiet: true }) { nil }

      expect(custom_ui.level).to eq("silent")
      expect(Bundler.ui).to eq(custom_ui)
    end

    it "silences UI when force_latest_compatible is false even without :quiet" do
      stub_gemfile_flow
      custom_ui = Bundler::UI::Shell.new

      safe_invoke(false, { ui: custom_ui }) { nil }

      expect(custom_ui.level).to eq("silent")
      expect(Bundler.ui).to eq(custom_ui)
    end

    it "does not silence UI when force_latest_compatible is true and :quiet is not set" do
      stub_gemfile_flow
      custom_ui = Bundler::UI::Shell.new

      safe_invoke(true, { ui: custom_ui }) { nil }

      expect(custom_ui.level).not_to eq("silent")
      expect(Bundler.ui).to eq(custom_ui)
    end

    it "uses the provided :ui option as Bundler.ui" do
      stub_gemfile_flow
      custom_ui = Bundler::UI::Shell.new

      safe_invoke(false, { ui: custom_ui, quiet: true }) { nil }

      expect(Bundler.ui).to eq(custom_ui)
      expect(Bundler.ui).to be_a(Bundler::UI::Shell)
    end

    it "creates a default Bundler::UI::Shell when no :ui option is given" do
      stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler.ui).to be_a(Bundler::UI::Shell)
      expect(Bundler.ui).not_to be_nil
    end

    it "raises ArgumentError for unknown options with a descriptive message" do
      stub_gemfile_flow

      expect {
        safe_invoke(false, { unknown_key: true }) { nil }
      }.to raise_error(ArgumentError, /Unknown options: unknown_key/)

      expect {
        safe_invoke(false, { foo: 1, bar: 2 }) { nil }
      }.to raise_error(ArgumentError, /Unknown options:/)
    end

    it "accepts the recognised :ui and :quiet options without raising" do
      stub_gemfile_flow

      expect {
        safe_invoke(false, { ui: Bundler::UI::Shell.new, quiet: true }) { nil }
      }.not_to raise_error

      expect {
        safe_invoke(false, { quiet: false }) { nil }
      }.not_to raise_error
    end
  end

  # ------------------------------------------------------------------
  # plugin integration
  # ------------------------------------------------------------------
  describe "plugin integration" do
    it "calls Bundler::Plugin.gemfile_install when plugins setting is enabled" do
      doubles = stub_gemfile_flow(plugins_enabled: true)

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Plugin).to have_received(:gemfile_install)
      expect(doubles[:builder]).to have_received(:instance_eval)
    end

    it "does not call Plugin.gemfile_install when plugins setting is disabled" do
      doubles = stub_gemfile_flow(plugins_enabled: false)
      allow(Bundler::Plugin).to receive(:gemfile_install)

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Plugin).not_to have_received(:gemfile_install)
      expect(doubles[:builder]).to have_received(:instance_eval)
    end
  end

  # ------------------------------------------------------------------
  # error handling and BUNDLE_GEMFILE environment restoration
  # ------------------------------------------------------------------
  describe "error handling" do
    it "restores BUNDLE_GEMFILE to its original value when an error occurs" do
      stub_gemfile_flow
      original_value = "error_test_gemfile_#{$$}"
      ENV["BUNDLE_GEMFILE"] = original_value

      allow(Bundler::Dsl).to receive(:new).and_raise(RuntimeError, "test error")

      expect {
        invoke_inline_gemfile(false, { quiet: true }) { nil }
      }.to raise_error(RuntimeError, "test error")

      expect(ENV["BUNDLE_GEMFILE"]).to eq(original_value)
    end

    it "restores BUNDLE_GEMFILE to the previous value after successful execution" do
      stub_gemfile_flow
      original_value = "original_gemfile_path_#{$$}"
      ENV["BUNDLE_GEMFILE"] = original_value

      invoke_inline_gemfile(false, { quiet: true }) { nil }

      expect(ENV["BUNDLE_GEMFILE"]).to eq(original_value)
      expect(original_value).not_to be_empty
    end

    it "sets BUNDLE_GEMFILE to empty string when no previous value existed" do
      stub_gemfile_flow
      ENV.delete("BUNDLE_GEMFILE")

      # Stub unbundle_env! to simulate ENV clearing during execution
      allow(Bundler).to receive(:unbundle_env!) do
        ENV.delete("BUNDLE_GEMFILE")
      end

      invoke_inline_gemfile(false, { quiet: true }) { nil }

      expect(ENV["BUNDLE_GEMFILE"]).to eq("")
      expect(ENV.key?("BUNDLE_GEMFILE")).to be true
    end

    it "propagates errors raised during definition validation" do
      doubles = stub_gemfile_flow
      allow(doubles[:definition]).to receive(:validate_runtime!)
        .and_raise(Bundler::GemNotFound, "Could not find gem")

      expect {
        safe_invoke(false, { quiet: true }) { nil }
      }.to raise_error(Bundler::GemNotFound, /Could not find gem/)

      expect(Bundler).to have_received(:reset!)
    end
  end

  # ------------------------------------------------------------------
  # default parameter values
  # ------------------------------------------------------------------
  describe "default parameter values" do
    it "defaults force_latest_compatible to false, skipping install and calling require" do
      doubles = stub_gemfile_flow

      safe_invoke { nil }

      expect(doubles[:definition]).to have_received(:missing_specs?)
      expect(Bundler::Installer).not_to have_received(:install)
      expect(doubles[:runtime]).to have_received(:require)
    end

    it "defaults options to empty hash allowing normal execution" do
      doubles = stub_gemfile_flow

      safe_invoke(false) { nil }

      expect(doubles[:runtime]).to have_received(:setup)
      expect(doubles[:runtime]).to have_received(:require)
    end
  end
end
