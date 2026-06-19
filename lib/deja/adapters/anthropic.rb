# frozen_string_literal: true

require "deja/adapters/base"
require "llm_mock_anthropic"

module Deja
  module Adapters
    # Wires the Anthropic provider from llm_mock_anthropic into Deja's cache.
    # All Anthropic-SDK shape knowledge — the stub client, the response structs,
    # and serialize/deserialize — lives in LlmMock::Anthropic; this adapter just
    # routes its calls through Deja::Cache (via Base#cached_call).
    class Anthropic < Base
      def provider
        @provider ||= LlmMock::Anthropic::Provider.new
      end

      def build_mock_client
        adapter = self
        provider.build_client do |method, kwargs|
          adapter.cached_call(method, kwargs) do
            adapter.provider.call_real(adapter.real_client, method, kwargs)
          end
        end
      end

      def default_real_client
        provider.default_real_client
      end

      def prompt_for(kwargs)
        provider.prompt_for(kwargs)
      end

      def serialize(method, response)
        provider.serialize(method, response)
      end

      def deserialize(method, data)
        provider.deserialize(method, data)
      end
    end

    register_type(:anthropic, Anthropic)
  end
end
