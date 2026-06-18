# frozen_string_literal: true

require "deja/cache"

module Deja
  # Cache layer behind the `meet_requirements` matcher (defined in deja/rspec.rb).
  # Stores confirmed requirement/value pairs keyed by a hash of the requirements
  # text. One file per test: `<cache_root>/meets_requirements/<suite>/<id>.yaml`.
  #
  #   test_suite: <derived from spec file path>
  #   test_name:  <full RSpec description>
  #   summary:    <human-readable counts: assertions / total confirmed values>
  #   assertions:
  #     - hash:         <12-char fingerprint of the requirements text — used for lookup>
  #       requirements: <the requirements text — auditable from the file alone>
  #       confirmed_values:
  #         - <values previously approved by the LLM judge>
  #
  # Pruning mirrors Deja::Cache: at the end of a passing example (when
  # ALLOW_LLM_CALL=1), assertions whose hash wasn't touched are dropped — so
  # changing the requirements text blows away the now-stale confirmed values.
  module RequirementsCache
    module_function

    def cache_dir
      Deja.configuration.cache_root!.join("meets_requirements")
    end

    def values_for(requirements)
      record_touched(requirements)
      assertion = load_assertion(requirements)
      assertion ? assertion.fetch("confirmed_values") : []
    end

    def append!(requirements, value)
      record_touched(requirements)
      data = load_or_init
      upsert_assertion(data, requirements, value)
      data["summary"] = build_summary(data["assertions"])
      cache_file.write(YAML.dump(Deja::Cache.stringify(data)))
    end

    def prune_untouched_in_current_example!
      return unless cache_file.exist?

      data = YAML.safe_load(cache_file.read)
      touched = touched_hashes
      fresh_assertions = data["assertions"].select {|a| touched.include?(a["hash"]) }
      return if fresh_assertions.size == data["assertions"].size

      if fresh_assertions.empty?
        cache_file.delete
      else
        data["assertions"] = fresh_assertions
        data["summary"] = build_summary(fresh_assertions)
        cache_file.write(YAML.dump(Deja::Cache.stringify(data)))
      end
    end

    def cache_file
      cache_dir.join(Deja::Cache.test_suite, "#{Deja::Cache.current_id!}.yaml")
    end

    def requirements_hash(requirements)
      Digest::SHA256.hexdigest(requirements.strip)[0, 12]
    end

    def load_assertion(requirements)
      return nil unless cache_file.exist?

      hash = requirements_hash(requirements)
      YAML.safe_load(cache_file.read).fetch("assertions").find {|a| a["hash"] == hash }
    end

    def load_or_init
      if cache_file.exist?
        YAML.safe_load(cache_file.read)
      else
        FileUtils.mkdir_p(cache_file.dirname)
        {
          "test_suite" => Deja::Cache.test_suite,
          "test_name" => Deja::Cache.current_test_name,
          "summary" => "",
          "assertions" => [],
        }
      end
    end

    def upsert_assertion(data, requirements, value)
      hash = requirements_hash(requirements)
      existing = data["assertions"].find {|a| a["hash"] == hash }
      if existing
        existing["confirmed_values"] = existing.fetch("confirmed_values") + [ value ]
      else
        data["assertions"] << {
          "hash" => hash,
          "requirements" => requirements.strip,
          "confirmed_values" => [ value ],
        }
      end
    end

    def build_summary(assertions)
      total_values = assertions.sum {|a| a["confirmed_values"].size }
      "#{assertions.size} #{assertions.size == 1 ? 'assertion' : 'assertions'}, " \
        "#{total_values} confirmed #{total_values == 1 ? 'value' : 'values'} total."
    end

    def record_touched(requirements)
      touched_hashes << requirements_hash(requirements)
    end

    def touched_hashes
      Deja::Cache.current_example!.metadata[:touched_meet_requirements_hashes] ||= Set.new
    end
  end
end
