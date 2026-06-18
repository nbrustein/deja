# frozen_string_literal: true

require "deja/cache"

module Deja
  # Hands your app a stub Anthropic client whose messages.create and
  # messages.stream route through Deja::Cache. Your app installs it via the
  # configured `install_client` seam (see Deja::Configuration). See Deja::Cache
  # for cache behavior and env flags.
  module AnthropicMock
    TextBlock = Struct.new(:type, :text)
    ToolUseBlock = Struct.new(:type, :id, :name, :input)
    Message = Struct.new(:content)
    Stream = Struct.new(:text, :accumulated_message)

    class << self
      attr_accessor :calls
    end
    self.calls = []

    module_function

    # Call from a spec (via `forbid_calls`) whose code path under test must not
    # reach the LLM — installs a client that raises on any access, so an
    # accidental real (or cached) call surfaces as a loud test failure.
    def forbid_calls
      install_into_example(poison_client)
    end

    # Call from a spec (via `use_llm_cache`) that should route Anthropic calls
    # through Deja::Cache. Resets the captured call log for the example.
    def enable
      self.calls = []
      install_into_example(install)
    end

    # Runs the host's configured install_client block in the current example's
    # context (so RSpec's `allow` is in scope), handing it `client` to return.
    def install_into_example(client)
      instance = RSpec.current_example&.example_group_instance
      raise Deja::Error, "Deja must be used inside an RSpec example" unless instance

      instance.instance_exec(client, &Deja.configuration.install_client)
    end

    def poison_client
      poison = Object.new
      def poison.method_missing(*) = raise("LLM should not be called (deja forbid_calls)")
      def poison.respond_to_missing?(*) = true
      poison
    end

    def install
      messages = build_messages_stub
      client = Object.new
      client.define_singleton_method(:messages) { messages }
      client
    end

    def build_messages_stub
      messages = Object.new

      messages.define_singleton_method(:create) do |**kwargs|
        AnthropicMock.calls << {method: :create, kwargs:}
        data = Deja::Cache.fetch(:create, kwargs) do
          response = AnthropicMock.real_client.messages.create(**kwargs)
          AnthropicMock.serialize_message(response)
        end
        AnthropicMock.deserialize_message(data)
      end

      messages.define_singleton_method(:stream) do |**kwargs|
        AnthropicMock.calls << {method: :stream, kwargs:}
        data = Deja::Cache.fetch(:stream, kwargs) do
          stream = AnthropicMock.real_client.messages.stream(**kwargs)
          AnthropicMock.serialize_stream(stream)
        end
        AnthropicMock.deserialize_stream(data)
      end

      messages
    end

    def real_client
      Deja.configuration.build_real_client.call
    end

    def serialize_message(message)
      {"content" => message.content.map {|block| serialize_block(block) }}
    end

    def serialize_block(block)
      case block.type.to_s
      when "tool_use"
        {"type" => "tool_use", "id" => block.id, "name" => block.name, "input" => block.input}
      else
        {"type" => block.type.to_s, "text" => block.text}
      end
    end

    def deserialize_message(data)
      blocks = data["content"].map {|b| deserialize_block(b) }
      Message.new(blocks)
    end

    def deserialize_block(data)
      case data["type"]
      when "tool_use"
        ToolUseBlock.new(:tool_use, data["id"], data["name"], data["input"])
      else
        TextBlock.new(data["type"].to_sym, data["text"])
      end
    end

    def serialize_stream(stream)
      text_chunks = stream.text.to_a
      {
        "text_chunks" => text_chunks,
        "content" => stream.accumulated_message.content.map {|block| serialize_block(block) },
      }
    end

    def deserialize_stream(data)
      blocks = (data["content"] || [ {"type" => "text", "text" => data["text_chunks"].join} ])
        .map {|b| deserialize_block(b) }
      Stream.new(data["text_chunks"].dup, Message.new(blocks))
    end

    # Asserts that exactly one LLM call was captured and returns its kwargs.
    # Must be called from within an RSpec example.
    def expect_llm_called
      instance = RSpec.current_example&.example_group_instance
      raise Deja::Error, "Deja must be used inside an RSpec example" unless instance

      instance.instance_exec do
        expect(AnthropicMock.calls.size).to eq(1)
      end
      AnthropicMock.calls.first[:kwargs]
    end
  end
end
