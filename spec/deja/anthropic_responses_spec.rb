# frozen_string_literal: true

RSpec.describe Deja::Anthropic do
  it "exposes the response structs Deja deserializes cached responses into" do
    expect(Deja::Anthropic::Message).to be(Deja::Adapters::Anthropic::Message)
    expect(Deja::Anthropic::Stream).to be(Deja::Adapters::Anthropic::Stream)
    expect(Deja::Anthropic::TextBlock).to be(Deja::Adapters::Anthropic::TextBlock)
    expect(Deja::Anthropic::ToolUseBlock).to be(Deja::Adapters::Anthropic::ToolUseBlock)
  end

  it "builds a tool_use message shaped like what app code consumes" do
    message = Deja::Anthropic::Message.new([
      Deja::Anthropic::ToolUseBlock.new(:tool_use, "id1", "do_thing", {"x" => 1}),
    ])
    block = message.content.first
    expect(block.type).to eq(:tool_use)
    expect(block.name).to eq("do_thing")
    expect(block.input).to eq({"x" => 1})
  end
end
