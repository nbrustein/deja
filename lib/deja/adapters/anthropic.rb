# frozen_string_literal: true

require "deja/adapters/base"

module Deja
  module Adapters
    # Records the Anthropic Ruby SDK: messages.create and messages.stream, with
    # text and tool_use blocks (and accumulated stream chunks). Use `::Anthropic`
    # for the SDK constant — bare `Anthropic` would resolve to this class.
    class Anthropic < Base
      TextBlock = Struct.new(:type, :text)
      ToolUseBlock = Struct.new(:type, :id, :name, :input)
      Message = Struct.new(:content)
      Stream = Struct.new(:text, :accumulated_message)

      def build_mock_client
        adapter = self
        messages = Object.new

        messages.define_singleton_method(:create) do |**kwargs|
          adapter.cached_call(:create, kwargs) { adapter.real_client.messages.create(**kwargs) }
        end

        messages.define_singleton_method(:stream) do |**kwargs|
          adapter.cached_call(:stream, kwargs) { adapter.real_client.messages.stream(**kwargs) }
        end

        client = Object.new
        client.define_singleton_method(:messages) { messages }
        client
      end

      def default_real_client
        -> { ::Anthropic::Client.new(api_key: ENV["CLAUDE_API_KEY"]) }
      end

      def prompt_for(kwargs)
        kwargs[:system].to_s
      end

      def serialize(method, response)
        method == :stream ? serialize_stream(response) : serialize_message(response)
      end

      def deserialize(method, data)
        method == :stream ? deserialize_stream(data) : deserialize_message(data)
      end

      private

      def serialize_message(message)
        build_response(message.content.map {|block| serialize_block(block) })
      end

      def serialize_stream(stream)
        build_response(
          stream.accumulated_message.content.map {|block| serialize_block(block) },
          text_chunks: stream.text.to_a,
        )
      end

      # The recorded `response` hash. `content` is what deserialize replays; the
      # `text_response`/`tool_uses` fields (and the file summary) are readable
      # conveniences derived from it.
      def build_response(blocks, text_chunks: nil)
        text_blocks = blocks.select {|b| b["type"] == "text" }
        tool_use_blocks = blocks.select {|b| b["type"] == "tool_use" }

        response = {}
        response["text_response"] = text_blocks.map {|b| b["text"] }.join("\n") unless text_blocks.empty?
        unless tool_use_blocks.empty?
          response["tool_uses"] = tool_use_blocks.map do |b|
            {"id" => b["id"], "name" => b["name"], "input" => b["input"]}
          end
        end
        response["content"] = blocks
        response["text_chunks"] = text_chunks if text_chunks
        response
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
        Message.new(data["content"].map {|b| deserialize_block(b) })
      end

      def deserialize_block(data)
        case data["type"]
        when "tool_use"
          ToolUseBlock.new(:tool_use, data["id"], data["name"], data["input"])
        else
          TextBlock.new(data["type"].to_sym, data["text"])
        end
      end

      def deserialize_stream(data)
        blocks = (data["content"] || [ {"type" => "text", "text" => data["text_chunks"].join} ])
          .map {|b| deserialize_block(b) }
        Stream.new(data["text_chunks"].dup, Message.new(blocks))
      end
    end

    register_type(:anthropic, Anthropic)
  end
end
