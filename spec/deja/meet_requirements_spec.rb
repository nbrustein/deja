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
end
