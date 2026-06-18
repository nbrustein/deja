# frozen_string_literal: true

require "deja"
require "rspec"
require "json"

module Deja
  # The test-facing DSL, mixed into every example by the RSpec.configure block
  # below. Require "deja/rspec" from your spec setup to install it.
  module Helpers
    # Call from the top of an `it` block (per-test — the id should be distinct
    # for each test) to install the caching client and set the cache id used for
    # this example.
    def use_llm_cache(id)
      RSpec.current_example.metadata[:llm_cache_id] = id
      Deja::Session.enable
    end

    # Assert the code path under test never reaches the LLM. Call from a `before`
    # block or the top of an example.
    def forbid_calls
      Deja::Session.forbid
    end

    # Assert exactly one LLM call happened (across all providers) and return its
    # kwargs.
    def expect_llm_called
      Deja::Session.expect_called
    end

    # Read a value from a recorded cache YAML file by walking `path`. Each segment
    # is a string key (for hashes) or an integer index (for arrays). Raises with
    # the path traversed so far if any segment is missing — so a renamed key or
    # shifted index fails loud rather than returning nil.
    #
    #   cached_llm_value("2026-04-30_17-03",
    #     "calls", 0, "response", "tool_uses", 0, "input", "session_instructions")
    def cached_llm_value(id, *path)
      file = Deja::Cache.cache_dir.join(Deja::Cache.test_suite, "#{id}.yaml")
      rel = Deja::Cache.display_path(file)
      raise "No cached LLM file at #{rel}" unless file.exist?

      current = YAML.safe_load(file.read)
      path.each_with_index do |segment, i|
        crumb = i.zero? ? "<root>" : path[0...i].map(&:inspect).join("/")
        current = case current
        when Hash
          unless current.key?(segment)
            raise "No key #{segment.inspect} at #{crumb} in #{rel}; available: #{current.keys.inspect}"
          end
          current[segment]
        when Array
          unless segment.is_a?(Integer)
            raise "Expected integer index at #{crumb} in #{rel}, got #{segment.inspect}"
          end
          unless segment < current.size
            raise "Index #{segment} out of range at #{crumb} (size #{current.size}) in #{rel}"
          end
          current[segment]
        else
          raise "Cannot traverse into #{current.class} at #{crumb} in #{rel}"
        end
      end
      current
    end
  end
end

# `meet_requirements(requirements_text)` asserts that an LLM-generated value
# satisfies a free-text description without pinning to a specific stringification.
#
# 1. Looks for the requirements_hash in the cache. If `actual` is already a
#    confirmed value, passes — no LLM call.
# 2. Otherwise, with ALLOW_LLM_CALL=1, asks the judge model whether `actual`
#    meets the requirements (structured output). On "yes", caches and passes.
# 3. Otherwise, fails telling you to re-record under ALLOW_LLM_CALL=1.
RSpec::Matchers.define :meet_requirements do |requirements|
  match do |actual|
    @requirements = requirements

    cached = Deja::RequirementsCache.values_for(requirements)
    next true if cached.include?(actual)

    unless ENV["ALLOW_LLM_CALL"]
      file = Deja::Cache.display_path(Deja::RequirementsCache.cache_file)
      @reason = "value is not in #{file} for the current requirements. " \
        "Set ALLOW_LLM_CALL=1 to verify it against the requirements via LLM and add it to the cache."
      next false
    end

    # Use the dedicated judge client — independent of whatever provider the spec
    # is recording, and outside the Deja::Cache layer. The meet_requirements cache
    # is the only cache that should track these calls.
    config = Deja.configuration
    judge_client = config.judge_client.call
    response = judge_client.messages.create(
      model: config.judge_model,
      max_tokens: config.judge_max_tokens,
      system: config.judge_system_prompt,
      messages: [
        {
          role: "user",
          content: "Requirements:\n#{requirements}\n\nCandidate value:\n#{actual}\n\n" \
            "Does the candidate value meet the requirements?",
        },
      ],
      output_config: {
        format: {
          type: :json_schema,
          schema: {
            "type" => "object",
            "properties" => {
              "meets_requirements" => {"type" => "boolean"},
              "reason" => {"type" => "string"},
            },
            "required" => [ "meets_requirements", "reason" ],
            "additionalProperties" => false,
          },
        },
      },
    )

    parsed = JSON.parse(response.content.first.text)
    if parsed["meets_requirements"]
      Deja::RequirementsCache.append!(requirements, actual)
      true
    else
      @reason = "LLM judge rejected the value: #{parsed['reason']}"
      false
    end
  end

  failure_message do |actual|
    "expected value to meet requirements\n#{@reason}\nGot: #{actual.inspect}"
  end
end

RSpec.configure do |config|
  config.include Deja::Helpers

  # Prune stale entries (calls/assertions whose hash wasn't looked up this
  # example) only when ALLOW_LLM_CALL=1 — the re-record path. Cache-only runs
  # leave both files alone so a temporarily-disabled call/assertion doesn't lose
  # its cached entry.
  config.after(:each) do |example|
    next if example.exception
    next unless example.metadata[:llm_cache_id]
    next unless ENV["ALLOW_LLM_CALL"]

    Deja::Cache.prune_untouched_in_current_example!
    Deja::RequirementsCache.prune_untouched_in_current_example!
  end
end
