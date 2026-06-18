# frozen_string_literal: true

require "pathname"

module Deja
  # Holds everything host-specific so the gem itself stays ignorant of your app.
  # You always set `cache_root` and register at least one provider; the judge
  # settings only matter if you use the `meet_requirements` matcher.
  class Configuration
    # Directory display in error messages is computed relative to this.
    attr_reader :cache_root, :project_root, :adapters

    # Judge call used by the `meet_requirements` matcher. Independent of the
    # providers under test — one consistent judge for the whole suite.
    attr_accessor :judge_model, :judge_max_tokens, :judge_system_prompt

    DEFAULT_JUDGE_SYSTEM_PROMPT =
      "You evaluate whether a candidate value meets a set of requirements. " \
      "Use the structured output schema to return your verdict."

    def initialize
      @cache_root = nil
      @project_root = Pathname.new(Dir.pwd)
      @judge_model = "claude-sonnet-4-5"
      @judge_max_tokens = 512
      @judge_system_prompt = DEFAULT_JUDGE_SYSTEM_PROMPT
      @judge_client = nil
      @adapters = {}
    end

    # Accepts a String or Pathname (e.g. Rails.root.join(...)).
    def cache_root=(value)
      @cache_root = value && Pathname.new(value.to_s)
    end

    def project_root=(value)
      @project_root = Pathname.new(value.to_s)
    end

    def cache_root!
      @cache_root || raise(Deja::Error, <<~MSG)
        Deja.configuration.cache_root is not set. Point it at a directory for the
        recorded cache, e.g.

          Deja.configure { |c| c.cache_root = "spec/support/cache" }
      MSG
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
