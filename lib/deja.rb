# frozen_string_literal: true

require "deja/version"

# Deja records a non-deterministic call (today: an Anthropic LLM call) the first
# time it happens and replays the recorded response on every run after that, so
# tests that exercise real model behavior stay fast, offline, and deterministic.
#
# Providers are pluggable via adapters (see Deja::Adapters) — a suite can mix
# them, and each test exercises whichever it actually calls.
#
# It also ships `meet_requirements`, an RSpec matcher that asserts an LLM-produced
# value satisfies a free-text description (judged once, then cached).
#
# See README.md for the full record/replay workflow and configuration.
module Deja
  class Error < StandardError; end

  # Raised on a cache miss when ALLOW_LLM_CALL is not set — i.e. replay mode hit
  # a request it has never recorded.
  class MissingCacheError < Error; end

  # Raised when an LLM call is made before `use_llm_cache(id)` set a cache id.
  class MissingIdError < Error; end

  class << self
    # Configure the gem. Yields the Configuration; returns it.
    #
    #   Deja.configure do |c|
    #     c.cache_root = Rails.root.join("spec/support/cache")
    #     c.register :anthropic,
    #       install: ->(client) { allow(AnthropicClient).to receive(:client).and_return(client) }
    #   end
    def configure
      yield(configuration)
      configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    # Drops configuration and the captured call log — used between examples and by
    # the gem's own suite.
    def reset_configuration!
      @configuration = Configuration.new
      reset_calls!
    end

    # Register a provider adapter (delegates to the configuration). See
    # Configuration#register.
    def register(provider, **opts)
      configuration.register(provider, **opts)
    end

    # The registered adapters, in registration order.
    def adapters
      configuration.adapters.values
    end

    # --- captured calls (reset per example by Session.enable) ---

    def calls
      @calls ||= []
    end

    def record_call(provider, method, kwargs)
      calls << {provider:, method:, kwargs:}
    end

    def reset_calls!
      @calls = []
    end
  end
end

require "deja/configuration"
require "deja/cache"
require "deja/requirements_cache"
require "deja/adapters/base"
require "deja/adapters/anthropic"
require "deja/judges/base"
require "deja/judges/anthropic"
require "deja/session"
