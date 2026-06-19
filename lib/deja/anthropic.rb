# frozen_string_literal: true

require "deja/adapters/anthropic"

module Deja
  # Stable, public names for the Anthropic response value objects Deja builds when
  # it deserializes a cached response. Use these to fabricate canned responses in
  # tests that stub the client directly — e.g. a system spec that returns a
  # scripted LLM response instead of recording/replaying — so those doubles match
  # exactly what cache replay produces.
  #
  #   client.define_singleton_method(:messages) { self }
  #   def client.create(**) = Deja::Anthropic::Message.new([
  #     Deja::Anthropic::ToolUseBlock.new(:tool_use, "id", "tool_name", {}),
  #   ])
  module Anthropic
    Message = Adapters::Anthropic::Message
    Stream = Adapters::Anthropic::Stream
    TextBlock = Adapters::Anthropic::TextBlock
    ToolUseBlock = Adapters::Anthropic::ToolUseBlock
  end
end
