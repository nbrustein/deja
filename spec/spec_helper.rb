# frozen_string_literal: true

require "deja/rspec"
require "tmpdir"
require "json"

require_relative "support/fakes"

# Helpers for the gem's own suite — toggle record mode and a fresh cache dir per
# example so tests never share state or touch the network.
module DejaSpecHelpers
  # Run the block with ALLOW_LLM_CALL=1 (record mode), restoring the prior value.
  def with_recording
    prev = ENV["ALLOW_LLM_CALL"]
    ENV["ALLOW_LLM_CALL"] = "1"
    yield
  ensure
    prev.nil? ? ENV.delete("ALLOW_LLM_CALL") : ENV["ALLOW_LLM_CALL"] = prev
  end

  # Configure Deja for this example: register the fake provider and, optionally, a
  # fake judge client for the meet_requirements matcher.
  def configure_deja(real_client: FakeRealClient.new { FakeRealClient.text("unused") }, judge_client: nil)
    Deja.configure do |c|
      c.cache_root = @deja_cache_root
      c.register :anthropic,
        install: ->(client) { allow(FakeApp).to receive(:client).and_return(client) },
        real_client: -> { real_client }
      c.judge_client { judge_client } if judge_client
    end
  end
end

RSpec.configure do |config|
  config.expect_with(:rspec) {|c| c.syntax = :expect }
  config.mock_with :rspec
  config.disable_monkey_patching!
  config.include DejaSpecHelpers

  # A clean configuration and an isolated cache dir for every example.
  config.around(:each) do |example|
    Dir.mktmpdir("deja-spec") do |dir|
      @deja_cache_root = dir
      Deja.reset_configuration!
      example.run
    end
  end
end
