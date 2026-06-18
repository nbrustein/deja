# frozen_string_literal: true

RSpec.describe "meet_requirements matcher" do
  def judge_returning(meets:, reason: "because")
    FakeRealClient.new do
      FakeRealClient.text(JSON.generate({"meets_requirements" => meets, "reason" => reason}))
    end
  end

  it "passes via the judge under ALLOW_LLM_CALL, then replays from cache" do
    judge = judge_returning(meets: true)
    configure_deja(judge_client: judge)
    use_llm_cache("req")

    with_recording do
      expect("a warm greeting").to meet_requirements("Should read as a friendly greeting")
    end
    expect(judge.create_count).to eq(1)

    # Cached: passes without ALLOW_LLM_CALL and without a second judge call.
    expect("a warm greeting").to meet_requirements("Should read as a friendly greeting")
    expect(judge.create_count).to eq(1)
  end

  it "fails (no recording) when the value isn't cached and ALLOW_LLM_CALL is unset" do
    configure_deja(judge_client: judge_returning(meets: true))
    use_llm_cache("req-uncached")

    expect { expect("x").to meet_requirements("must already be cached") }
      .to raise_error(RSpec::Expectations::ExpectationNotMetError, /Set ALLOW_LLM_CALL=1/)
  end

  it "fails when the judge rejects the value" do
    configure_deja(judge_client: judge_returning(meets: false, reason: "too formal"))
    use_llm_cache("req-rejected")

    with_recording do
      expect { expect("Dear Sir or Madam").to meet_requirements("Should be casual") }
        .to raise_error(RSpec::Expectations::ExpectationNotMetError, /too formal/)
    end
  end

  it "merges judge_attrs into the judge call, with reserved keys winning" do
    captured = nil
    judge = FakeRealClient.new do |kwargs|
      captured = kwargs
      FakeRealClient.text(JSON.generate({"meets_requirements" => true, "reason" => "ok"}))
    end
    configure_deja(judge_client: judge)
    Deja.configure do |c|
      c.judge_attrs = {
        model: "claude-opus-4-8",
        temperature: 0,
        messages: [ {role: "user", content: "HIJACK"} ], # reserved — must be ignored
      }
    end
    use_llm_cache("req-attrs")

    with_recording do
      expect("x").to meet_requirements("some requirement")
    end

    expect(captured[:model]).to eq("claude-opus-4-8")  # override applied
    expect(captured[:max_tokens]).to eq(512)           # default preserved
    expect(captured[:temperature]).to eq(0)            # arbitrary arg passed through
    expect(captured[:messages].first[:content]).to include("some requirement") # reserved key won
  end

  it "raises a clear error when no judge adapter handles the judge_client" do
    configure_deja(judge_client: Object.new) # no adapter handles a bare Object
    use_llm_cache("req-unknown-judge")

    with_recording do
      expect { expect("x").to meet_requirements("some requirement") }
        .to raise_error(Deja::Error, /No Deja judge adapter handles/)
    end
  end

  it "raises a clear error when a judge call is needed but judge_client isn't set" do
    configure_deja # no judge_client
    use_llm_cache("req-no-judge")

    with_recording do
      expect { expect("x").to meet_requirements("some requirement") }
        .to raise_error(Deja::Error, /judge_client is not set/)
    end
  end
end
