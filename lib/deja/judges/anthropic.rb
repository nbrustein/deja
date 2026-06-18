# frozen_string_literal: true

require "deja/judges/base"

module Deja
  module Judges
    # Judge backed by the Anthropic Ruby SDK. Use `::Anthropic` for the SDK
    # constant — bare `Anthropic` would resolve to this class.
    class Anthropic < Base
      DEFAULTS = {
        model: "claude-sonnet-4-5",
        max_tokens: 512,
        system: "You evaluate whether a candidate value meets a set of requirements. " \
          "Use the structured output schema to return your verdict.",
      }.freeze

      def self.handles?(client)
        defined?(::Anthropic::Client) && client.is_a?(::Anthropic::Client)
      end

      def self.client_description
        "Anthropic::Client"
      end

      def defaults
        DEFAULTS
      end
    end

    register(Anthropic)
  end
end
