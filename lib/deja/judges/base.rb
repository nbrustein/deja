# frozen_string_literal: true

module Deja
  # Judge adapters teach the `meet_requirements` matcher how to judge with a given
  # LLM client. An adapter is selected by the *type* of the object your
  # `judge_client` returns, so the right defaults follow from the provider you
  # chose rather than being assumed globally.
  #
  # Today an adapter supplies the default request attrs (model, etc.). The matcher
  # still builds the request and parses the response (both Anthropic-shaped); as
  # more judge providers are added, that construction/parsing is meant to move
  # onto the adapter too — which is why dispatch already happens here.
  module Judges
    @registered = []

    class << self
      # Built-in judge adapters register themselves. Newest-first, so a more
      # specific adapter registered later can shadow a more general one.
      def register(klass)
        @registered.unshift(klass)
      end

      def registered
        @registered
      end

      # The adapter for the client your `judge_client` returned. Raises a helpful
      # error when no registered adapter handles it.
      def for_client(client)
        klass = @registered.find {|k| k.handles?(client) }
        klass or raise Deja::Error, <<~MSG
          No Deja judge adapter handles #{client.class} (the object your
          judge_client returned). Deja can judge with: #{descriptions}.
          Point judge_client at one of those, or add a Deja::Judges::Base
          subclass that handles your client.
        MSG
        klass.new(client)
      end

      def descriptions
        @registered.map(&:client_description).join(", ")
      end
    end

    class Base
      attr_reader :client

      def initialize(client)
        @client = client
      end

      # Does this adapter handle the given judge-client instance?
      def self.handles?(_client)
        raise NotImplementedError, "#{name} must implement .handles?"
      end

      # Human-readable client name, used in error messages.
      def self.client_description
        name
      end

      # Default request attrs for this judge (model, etc.). The matcher merges the
      # user's judge_attrs over these, then its own reserved keys over both.
      def defaults
        raise NotImplementedError, "#{self.class} must implement #defaults"
      end
    end
  end
end
