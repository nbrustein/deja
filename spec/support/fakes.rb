# frozen_string_literal: true

# Stand-in for a host app's LLM client accessor (e.g. `AnthropicClient.client`).
# Deja stubs `.client` via a registered adapter's install seam.
class FakeApp
  def self.client
    raise "FakeApp.client must be stubbed by Deja"
  end
end

# A fake "real" Anthropic client: shaped like the SDK (messages.create returning
# an object with `.content` blocks) but driven by a responder block, and counting
# calls so specs can prove replay never reaches it.
class FakeRealClient
  Block = Struct.new(:type, :text, :id, :name, :input)
  Message = Struct.new(:content)

  attr_reader :create_count

  def initialize(&responder)
    @responder = responder
    @create_count = 0
  end

  def messages
    self
  end

  def create(**kwargs)
    @create_count += 1
    @responder.call(kwargs)
  end

  def self.text(text)
    Message.new([ Block.new("text", text) ])
  end

  def self.tool_use(id:, name:, input:)
    Message.new([ Block.new("tool_use", nil, id, name, input) ])
  end
end

# Judge adapter for the fake client, so `meet_requirements` can judge in specs.
# Mirrors how Deja ships Deja::Judges::Anthropic for real Anthropic clients.
class FakeJudge < Deja::Judges::Base
  DEFAULTS = { model: "fake-judge", max_tokens: 512, system: "fake judge prompt" }.freeze

  def self.handles?(client) = client.is_a?(FakeRealClient)
  def self.client_description = "FakeRealClient"
  def defaults = DEFAULTS
end

Deja::Judges.register(FakeJudge)
