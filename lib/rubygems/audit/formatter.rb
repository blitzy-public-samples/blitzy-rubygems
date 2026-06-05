# frozen_string_literal: true

##
# Gem::Audit::Formatter is the registry/abstraction for audit output
# formatters. Concrete formatters self-register under a name and implement the
# class method +print_report(report, io)+, writing all output to the injected
# +io+ stream (never a hard-coded global).
#
# The registry maps a normalized format name (e.g. "text", "json") to the
# formatter class that renders an audit report in that format. The audit
# command selects a formatter with Gem::Audit::Formatter.for(name) and invokes
# +print_report+ on the returned class.

module Gem::Audit::Formatter
  ##
  # The format-name => formatter-class registry. Keys are normalized to
  # strings; the hash is created lazily on first access.

  def self.registry
    @registry ||= {}
  end

  ##
  # Register +klass+ as the formatter for +name+. The +name+ is normalized to a
  # string so lookups are insensitive to Symbol vs String callers.

  def self.register(name, klass)
    registry[name.to_s] = klass
  end

  ##
  # Look up the formatter class registered under +name+. Raises
  # Gem::CommandLineError if no formatter is registered for the given name.
  #
  # This raise is an internal safety net only: the audit command validates the
  # +--format+ value against the supported set before calling this method and
  # owns the user-facing error message.

  def self.for(name)
    registry.fetch(name.to_s) do
      raise Gem::CommandLineError, "unknown audit format: #{name}"
    end
  end

  class << self
    ##
    # +fetch+ is an alias for +for+, looking up a formatter class by name.
    alias_method :fetch, :for
  end
end

require_relative "formatter/text"
require_relative "formatter/json"
