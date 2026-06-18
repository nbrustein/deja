# frozen_string_literal: true

module Deja
  # Adapters teach Deja how to talk to one LLM provider: the stub client's shape,
  # how to (de)serialize a response, and how to build a real client. The cache,
  # hashing, and matcher are all provider-agnostic and live elsewhere.
  module Adapters
    @registered = {}

    class << self
      # Built-in adapter classes register themselves by provider name, so
      # `c.register :anthropic, ...` knows which class to build. A new provider is
      # purely additive: a new Base subclass + one register_type call.
      def register_type(name, klass)
        @registered[name] = klass
      end

      def build(provider, key:, install:, real_client:)
        klass = @registered.fetch(provider) do
          raise Deja::Error, "Unknown provider #{provider.inspect}. Registered: #{@registered.keys.inspect}"
        end
        klass.new(key:, install:, real_client:)
      end
    end

    class Base
      attr_reader :key, :install_block

      # key          — how this registration is named (usually the provider symbol)
      # install      — block run in the example's context to swap the app's client
      #                for the one Deja hands it
      # real_client  — optional block building a live client; falls back to the
      #                subclass default
      def initialize(key:, install:, real_client: nil)
        @key = key
        @install_block = install
        @real_client_override = real_client
      end

      def real_client
        (@real_client_override || default_real_client).call
      end

      # Wraps a single call: records it (for expect_llm_called), routes through the
      # cache, and (de)serializes via the subclass. `real_call` performs the live
      # provider call when recording.
      def cached_call(method, kwargs, &real_call)
        Deja.record_call(key, method, kwargs)
        data = Deja::Cache.fetch(method, kwargs, provider: key, prompt: prompt_for(kwargs)) do
          serialize(method, real_call.call)
        end
        deserialize(method, data)
      end

      # --- subclass hooks ---

      # The stub client object the app receives. Its methods call `cached_call`.
      def build_mock_client
        raise NotImplementedError, "#{self.class} must implement #build_mock_client"
      end

      # Provider response object -> plain Hash (must round-trip through deserialize).
      def serialize(_method, _response)
        raise NotImplementedError, "#{self.class} must implement #serialize"
      end

      # Plain Hash (from the cache) -> object shaped like the provider's response.
      def deserialize(_method, _data)
        raise NotImplementedError, "#{self.class} must implement #deserialize"
      end

      def default_real_client
        raise NotImplementedError, "#{self.class} must implement #default_real_client"
      end

      # A human-readable prompt string stored on the cache entry (purely for
      # auditing the YAML). Optional.
      def prompt_for(_kwargs)
        nil
      end
    end
  end
end
