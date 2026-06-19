# frozen_string_literal: true

require "pathname"

module Deja
  # Holds everything host-specific so the gem itself stays ignorant of your app.
  # You register at least one provider; cache_root has a sensible default, and the
  # judge settings only matter if you use the `meet_requirements` matcher.
  class Configuration
    # Directory display in error messages is computed relative to this.
    attr_reader :project_root, :adapters

    # Default recorded-cache location, relative to project_root.
    DEFAULT_CACHE_SUBPATH = "spec/support/deja_cache"

    # Attrs that override the `meet_requirements` judge's defaults. Set
    # provider-specific args here (model, temperature, …) without Deja having to
    # name each one — different judge LLMs expose different args. The defaults
    # themselves live with the judge code, not here, since they're specific to
    # whatever LLM the judge speaks. `messages` and `output_config` are reserved
    # by the matcher and can't be overridden.
    attr_writer :judge_attrs

    def initialize
      @cache_root = nil
      @project_root = Pathname.new(Dir.pwd)
      @judge_attrs = {}
      @judge_client = nil
      @adapters = {}
    end

    def judge_attrs
      @judge_attrs || {}
    end

    # Where recorded cache files live. Defaults to project_root/spec/support/deja_cache.
    def cache_root
      @cache_root || project_root.join(DEFAULT_CACHE_SUBPATH)
    end

    # Accepts a String or Pathname (e.g. Rails.root.join(...)).
    def cache_root=(value)
      @cache_root = value && Pathname.new(value.to_s)
    end

    def project_root=(value)
      @project_root = Pathname.new(value.to_s)
    end

    # Register a provider adapter. `provider` is a built-in adapter name (today:
    # `:anthropic`). `install` swaps your app's client for Deja's stub and runs in
    # the example's context (RSpec's `allow` is available). `real_client` is an
    # optional block building a live client; it defaults per provider. `as` names
    # the registration when you want two of the same provider.
    #
    #   c.register :anthropic,
    #     install: ->(client) { allow(AnthropicClient).to receive(:client).and_return(client) },
    #     real_client: -> { Anthropic::Client.new(api_key: my_key) }
    def register(provider, install:, real_client: nil, as: provider)
      @adapters[as] = Deja::Adapters.build(provider, key: as, install:, real_client:)
    end

    # How to build the client used by the `meet_requirements` judge. Required if
    # you use that matcher — there is no default, so the judge's auth/model is an
    # explicit choice. The block returns a client.
    #
    #   c.judge_client { Anthropic::Client.new }
    #
    # Called with no block, returns the configured proc (raises if unset).
    def judge_client(&block)
      if block
        @judge_client = block
      else
        @judge_client || raise(Deja::Error, <<~MSG)
          Deja.configuration.judge_client is not set. The `meet_requirements`
          matcher needs a client to judge values against requirements. Set one in
          your Deja.configure block:

            Deja.configure do |c|
              c.judge_client { Anthropic::Client.new }
            end
        MSG
      end
    end
  end
end
