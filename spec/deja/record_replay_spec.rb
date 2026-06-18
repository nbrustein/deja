# frozen_string_literal: true

RSpec.describe "Deja record + replay" do
  def create(content)
    FakeApp.client.messages.create(
      model: "claude-test",
      max_tokens: 16,
      messages: [ {role: "user", content:} ],
    )
  end

  it "records on the first call and replays without hitting the real client" do
    real = FakeRealClient.new {|kw| FakeRealClient.text("echo: #{kw[:messages].last[:content]}") }
    configure_deja(real_client: real)
    use_llm_cache("round-trip")

    recorded = with_recording { create("hi") }
    expect(recorded.content.first.text).to eq("echo: hi")
    expect(real.create_count).to eq(1)

    replayed = create("hi")
    expect(replayed.content.first.text).to eq("echo: hi")
    expect(real.create_count).to eq(1) # cache hit — real client not called again
  end

  it "raises MissingCacheError when replaying an unrecorded request" do
    configure_deja(real_client: FakeRealClient.new { FakeRealClient.text("x") })
    use_llm_cache("missing")

    expect { create("never recorded") }
      .to raise_error(Deja::MissingCacheError, /No cached LLM response/)
  end

  it "raises MissingIdError when no cache id was set" do
    configure_deja(real_client: FakeRealClient.new { FakeRealClient.text("x") })
    Deja::AnthropicMock.enable # install the stub without use_llm_cache

    expect { with_recording { create("hi") } }
      .to raise_error(Deja::MissingIdError, /use_llm_cache/)
  end

  it "round-trips tool_use blocks and reads input via cached_llm_value" do
    real = FakeRealClient.new { FakeRealClient.tool_use(id: "t1", name: "emit", input: {"x" => 1}) }
    configure_deja(real_client: real)
    use_llm_cache("tools")

    with_recording { create("go") }
    expect(cached_llm_value("tools", "calls", 0, "response", "tool_uses", 0, "input")).to eq({"x" => 1})

    block = create("go").content.first
    expect(block.type).to eq(:tool_use)
    expect(block.name).to eq("emit")
    expect(block.input).to eq({"x" => 1})
  end

  describe "expect_llm_called" do
    it "returns the kwargs of the single captured call" do
      configure_deja(real_client: FakeRealClient.new { FakeRealClient.text("ok") })
      use_llm_cache("single")

      with_recording do
        FakeApp.client.messages.create(
          model: "claude-test", max_tokens: 16, system: "be terse",
          messages: [ {role: "user", content: "yo"} ],
        )
      end

      kwargs = expect_llm_called
      expect(kwargs[:system]).to eq("be terse")
    end
  end

  describe "forbid_calls" do
    it "makes any access to the client raise" do
      configure_deja(real_client: FakeRealClient.new { FakeRealClient.text("ok") })
      forbid_calls

      expect { FakeApp.client.messages }.to raise_error(/should not be called/)
    end
  end
end
