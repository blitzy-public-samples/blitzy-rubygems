# frozen_string_literal: true

require "spec_helper"
require "bundler/inline"

# The gemfile method from bundler/inline is defined on Object, but the Bundler test
# helpers (Spec::Helpers) define their own gemfile method for writing Gemfile contents.
# We capture a reference to the production gemfile method to invoke it directly.
INLINE_GEMFILE_METHOD = Object.instance_method(:gemfile)

RSpec.describe "Bundler inline gemfile" do
  # Helper to invoke the real production gemfile method from bundler/inline,
  # bypassing the Spec::Helpers#gemfile test helper that shadows it.
  def invoke_inline_gemfile(force_latest_compatible = false, options = {}, &block)
    INLINE_GEMFILE_METHOD.bind_call(self, force_latest_compatible, options, &block)
  end

  # Save and restore Bundler.ui around each example to prevent stale mock
  # references from leaking into the spec_helper around(:each) hook which
  # calls Bundler.ui.silence { example.run }.
  around(:each) do |example|
    saved_ui = Bundler.ui
    example.run
  ensure
    Bundler.ui = saved_ui
  end

  # Shared helper that stubs out the full gemfile method flow so production
  # code can execute without real side-effects. Returns a hash of doubles
  # for assertion.
  def stub_gemfile_flow(missing_specs: false, plugins_enabled: false)
    builder = instance_double(Bundler::Dsl)
    definition = double("Definition")
    runtime = double("Runtime")
    installer = double("Installer", post_install_messages: {})
    settings = double("Settings")

    # Bundler reset and environment
    allow(Bundler).to receive(:reset!)
    allow(Bundler).to receive(:unbundle_env!)
    allow(Bundler).to receive(:instance_variable_set)
    allow(Bundler::SharedHelpers).to receive(:set_env)
    allow(Bundler).to receive(:root).and_return(Pathname.new("."))

    # Settings
    allow(settings).to receive(:[]) do |key|
      key == :plugins ? plugins_enabled : nil
    end
    allow(settings).to receive(:temporary).and_yield
    allow(Bundler).to receive(:settings).and_return(settings)

    # Plugin
    allow(Bundler::Plugin).to receive(:gemfile_install) if plugins_enabled

    # DSL and definition
    allow(Bundler::Dsl).to receive(:new).and_return(builder)
    allow(builder).to receive(:instance_eval)
    allow(builder).to receive(:to_definition).and_return(definition)
    allow(definition).to receive(:validate_runtime!)
    allow(definition).to receive(:missing_specs?).and_return(missing_specs)

    # Installer
    allow(Bundler::Installer).to receive(:install).and_return(installer)

    # Runtime
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
  # the test environment is not permanently changed.
  def safe_invoke(force_latest_compatible = false, options = {}, &block)
    old = ENV["BUNDLE_GEMFILE"]
    invoke_inline_gemfile(force_latest_compatible, options, &block)
  ensure
    ENV["BUNDLE_GEMFILE"] = old || ""
  end

  # ------------------------------------------------------------------
  # Method availability
  # ------------------------------------------------------------------
  describe "gemfile method availability" do
    it "is defined on Object after requiring bundler/inline" do
      unbound = Object.instance_method(:gemfile)
      expect(unbound).to be_a(UnboundMethod)
      expect(unbound.arity).to eq(-1)
    end

    it "accepts force_latest_compatible, options, and a block parameter" do
      params = Object.instance_method(:gemfile).parameters
      expect(params).to include([:opt, :force_latest_compatible])
      expect(params).to include([:opt, :options])
      expect(params).to include([:block, :gemfile])
    end
  end

  # ------------------------------------------------------------------
  # Option validation
  # ------------------------------------------------------------------
  describe "option validation" do
    it "raises ArgumentError for unknown options" do
      stub_gemfile_flow

      expect {
        safe_invoke(false, { unknown_key: true }) { nil }
      }.to raise_error(ArgumentError, /Unknown options: unknown_key/)
    end

    it "raises ArgumentError listing multiple unknown options" do
      stub_gemfile_flow

      expect {
        safe_invoke(false, { foo: 1, bar: 2 }) { nil }
      }.to raise_error(ArgumentError, /Unknown options:/)
    end

    it "does not raise for recognised :ui and :quiet options" do
      stub_gemfile_flow

      expect {
        safe_invoke(false, { ui: Bundler::UI::Shell.new, quiet: true }) { nil }
      }.not_to raise_error
    end
  end

  # ------------------------------------------------------------------
  # UI configuration
  # ------------------------------------------------------------------
  describe "UI configuration" do
    it "sets Bundler.ui to the provided :ui option" do
      stub_gemfile_flow
      custom_ui = Bundler::UI::Shell.new

      safe_invoke(false, { ui: custom_ui, quiet: true }) { nil }

      expect(Bundler.ui).to eq(custom_ui)
    end

    it "creates a new Bundler::UI::Shell when no :ui option given" do
      stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler.ui).to be_a(Bundler::UI::Shell)
    end

    it "sets UI level to silent when :quiet is true" do
      stub_gemfile_flow
      custom_ui = Bundler::UI::Shell.new

      safe_invoke(true, { ui: custom_ui, quiet: true }) { nil }

      # :quiet forces silent regardless of force_latest_compatible
      expect(custom_ui.level).to eq("silent")
    end

    it "sets UI level to silent when force_latest_compatible is false" do
      stub_gemfile_flow
      custom_ui = Bundler::UI::Shell.new

      safe_invoke(false, { ui: custom_ui }) { nil }

      # !force_latest_compatible means silent
      expect(custom_ui.level).to eq("silent")
    end

    it "does not silence UI when force_latest_compatible is true and quiet is not set" do
      stub_gemfile_flow
      custom_ui = Bundler::UI::Shell.new
      original_level = custom_ui.level

      safe_invoke(true, { ui: custom_ui }) { nil }

      # force_latest_compatible=true without :quiet means NOT silenced
      expect(custom_ui.level).not_to eq("silent")
    end
  end

  # ------------------------------------------------------------------
  # Bundler reset and environment management
  # ------------------------------------------------------------------
  describe "Bundler reset and environment management" do
    it "calls Bundler.reset! at the start of gemfile execution" do
      stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler).to have_received(:reset!)
    end

    it "calls Bundler.unbundle_env!" do
      stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler).to have_received(:unbundle_env!)
    end

    it "restores BUNDLE_GEMFILE after execution" do
      stub_gemfile_flow
      original_value = "original_gemfile_path_#{$$}"
      ENV["BUNDLE_GEMFILE"] = original_value

      invoke_inline_gemfile(false, { quiet: true }) { nil }

      expect(ENV["BUNDLE_GEMFILE"]).to eq(original_value)
    end

    it "sets BUNDLE_GEMFILE to empty string when no previous value existed" do
      stub_gemfile_flow
      ENV.delete("BUNDLE_GEMFILE")

      # unbundle_env! may clear ENV vars; stub it to clear BUNDLE_GEMFILE
      allow(Bundler).to receive(:unbundle_env!) do
        ENV.delete("BUNDLE_GEMFILE")
      end

      invoke_inline_gemfile(false, { quiet: true }) { nil }

      expect(ENV["BUNDLE_GEMFILE"]).to eq("")
    end

    it "restores BUNDLE_GEMFILE even when an error occurs" do
      stub_gemfile_flow
      original_value = "error_test_gemfile_#{$$}"
      ENV["BUNDLE_GEMFILE"] = original_value

      # Force an error after BUNDLE_GEMFILE is saved
      allow(Bundler::Dsl).to receive(:new).and_raise(RuntimeError, "test error")

      expect {
        invoke_inline_gemfile(false, { quiet: true }) { nil }
      }.to raise_error(RuntimeError, "test error")

      expect(ENV["BUNDLE_GEMFILE"]).to eq(original_value)
    end
  end

  # ------------------------------------------------------------------
  # DSL evaluation
  # ------------------------------------------------------------------
  describe "DSL evaluation" do
    it "creates a new Bundler::Dsl and evaluates the block on it" do
      doubles = stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Dsl).to have_received(:new)
      expect(doubles[:builder]).to have_received(:instance_eval)
    end

    it "converts the DSL builder to a definition with nil lockfile and unlock=true" do
      doubles = stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(doubles[:builder]).to have_received(:to_definition).with(nil, true)
    end
  end

  # ------------------------------------------------------------------
  # Installation behavior
  # ------------------------------------------------------------------
  describe "installation behavior" do
    it "triggers installation when force_latest_compatible is true" do
      stub_gemfile_flow

      safe_invoke(true, { quiet: true }) { nil }

      expect(Bundler::Installer).to have_received(:install)
        .with(Pathname.new("."), anything, hash_including(system: true))
    end

    it "triggers installation when definition has missing specs" do
      stub_gemfile_flow(missing_specs: true)

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Installer).to have_received(:install)
    end

    it "skips installation when force_latest_compatible is false and no missing specs" do
      stub_gemfile_flow(missing_specs: false)

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Installer).not_to have_received(:install)
    end

    it "outputs post-install messages from installed gems" do
      doubles = stub_gemfile_flow
      allow(doubles[:installer]).to receive(:post_install_messages)
        .and_return({ "mygem" => "Hello from mygem!" })

      custom_ui = Bundler::UI::Shell.new
      output = StringIO.new
      # Replace the UI's output to capture messages
      allow(custom_ui).to receive(:info).and_call_original

      safe_invoke(true, { ui: custom_ui }) { nil }

      expect(custom_ui).to have_received(:info)
        .with("Post-install message from mygem:\nHello from mygem!")
    end
  end

  # ------------------------------------------------------------------
  # Runtime setup
  # ------------------------------------------------------------------
  describe "runtime setup" do
    it "creates a Runtime with nil root and the definition, then calls setup and require" do
      doubles = stub_gemfile_flow

      # Override to verify exact arguments
      allow(Bundler::Runtime).to receive(:new)
        .with(nil, doubles[:definition])
        .and_return(doubles[:runtime])

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Runtime).to have_received(:new).with(nil, doubles[:definition])
      expect(doubles[:runtime]).to have_received(:setup)
      expect(doubles[:runtime]).to have_received(:require)
    end
  end

  # ------------------------------------------------------------------
  # Plugin integration
  # ------------------------------------------------------------------
  describe "plugin integration" do
    it "calls Bundler::Plugin.gemfile_install when plugins setting is enabled" do
      stub_gemfile_flow(plugins_enabled: true)

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Plugin).to have_received(:gemfile_install)
    end

    it "does not call Plugin.gemfile_install when plugins setting is disabled" do
      stub_gemfile_flow(plugins_enabled: false)
      allow(Bundler::Plugin).to receive(:gemfile_install)

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::Plugin).not_to have_received(:gemfile_install)
    end
  end

  # ------------------------------------------------------------------
  # Settings configuration
  # ------------------------------------------------------------------
  describe "settings configuration" do
    it "uses temporary settings with deployment:false and frozen:false" do
      doubles = stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(doubles[:settings]).to have_received(:temporary)
        .with(deployment: false, frozen: false)
    end

    it "sets bundle path to Gem.dir wrapped in a Pathname" do
      stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler).to have_received(:instance_variable_set)
        .with(:@bundle_path, Pathname.new(Gem.dir))
    end
  end

  # ------------------------------------------------------------------
  # BUNDLE_GEMFILE environment variable
  # ------------------------------------------------------------------
  describe "BUNDLE_GEMFILE environment variable" do
    it "sets BUNDLE_GEMFILE to 'Gemfile' via SharedHelpers during execution" do
      stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(Bundler::SharedHelpers).to have_received(:set_env)
        .with("BUNDLE_GEMFILE", "Gemfile")
    end
  end

  # ------------------------------------------------------------------
  # Definition validation
  # ------------------------------------------------------------------
  describe "definition validation" do
    it "calls validate_runtime! on the definition" do
      doubles = stub_gemfile_flow

      safe_invoke(false, { quiet: true }) { nil }

      expect(doubles[:definition]).to have_received(:validate_runtime!)
    end
  end

  # ------------------------------------------------------------------
  # Default parameter values
  # ------------------------------------------------------------------
  describe "default parameter values" do
    it "defaults force_latest_compatible to false (no install, runtime require)" do
      doubles = stub_gemfile_flow

      # Call with only a block (defaults for both positional args)
      safe_invoke { nil }

      # When force_latest_compatible defaults to false and no missing specs,
      # installation should be skipped and runtime.require should be called
      expect(doubles[:definition]).to have_received(:missing_specs?)
      expect(Bundler::Installer).not_to have_received(:install)
      expect(doubles[:runtime]).to have_received(:require)
    end
  end
end
