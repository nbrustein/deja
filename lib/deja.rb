# frozen_string_literal: true

require "deja/version"

# Deja records a non-deterministic call (today: an Anthropic LLM call) the first
# time it happens and replays the recorded response on every run after that, so
# tests that exercise real model behavior stay fast, offline, and deterministic.
#
# It also ships `meet_requirements`, an RSpec matcher that asserts an LLM-produced
# value satisfies a free-text description (judged once by the model, then cached)
# instead of pinning to an exact string.
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
    #     c.install_client { |client| allow(AnthropicClient).to receive(:client).and_return(client) }
    #   end
    def configure
      yield(configuration)
      configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    # Mostly for the gem's own test suite — drops any configuration so the next
    # `configuration` call starts fresh.
    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end

require "deja/configuration"
require "deja/cache"
require "deja/anthropic_mock"
require "deja/requirements_cache"
