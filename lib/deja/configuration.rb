# frozen_string_literal: true

require "pathname"

module Deja
  # Holds everything host-specific so the gem itself stays ignorant of your app.
  # The two seams you usually have to set are `cache_root` (where the recorded
  # YAML lives) and `install_client` (how to swap your app's LLM client for
  # Deja's caching stub).
  class Configuration
    # Directory display in error messages is computed relative to this.
    attr_reader :cache_root, :project_root

    # Judge call used by the `meet_requirements` matcher. Override the model when
    # you want a cheaper/stronger judge; override the prompt for domain framing.
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
      @build_real_client = nil
      @install_client = nil
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

    # How to install Deja's caching client into your app for the duration of a
    # test. The block runs in the RSpec example's context (so RSpec's `allow` is
    # available) and receives the stub client to return.
    #
    #   c.install_client { |client| allow(AnthropicClient).to receive(:client).and_return(client) }
    #
    # Called with no block, returns the configured proc (raises if unset).
    def install_client(&block)
      if block
        @install_client = block
      else
        @install_client || raise(Deja::Error, <<~MSG)
          Deja.configuration.install_client is not configured. Provide a block that
          stubs your app's LLM client with the one Deja hands it, e.g.

            Deja.configure do |c|
              c.install_client { |client| allow(AnthropicClient).to receive(:client).and_return(client) }
            end
        MSG
      end
    end

    # How to build a *real* (un-stubbed) Anthropic client. Used to record live
    # responses (ALLOW_LLM_CALL=1) and for the `meet_requirements` judge call.
    # Defaults to an Anthropic client keyed by ENV["CLAUDE_API_KEY"].
    #
    #   c.build_real_client { Anthropic::Client.new(api_key: ENV["CLAUDE_API_KEY"]) }
    #
    # Called with no block, returns the configured (or default) proc.
    def build_real_client(&block)
      if block
        @build_real_client = block
      else
        @build_real_client || default_real_client_builder
      end
    end

    private

    def default_real_client_builder
      -> { Anthropic::Client.new(api_key: ENV["CLAUDE_API_KEY"]) }
    end
  end
end
