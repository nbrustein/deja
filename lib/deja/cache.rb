# frozen_string_literal: true

require "diff/lcs"
require "diff/lcs/hunk"
require "digest"
require "fileutils"
require "set"
require "yaml"

module Deja
  # File-based cache for Anthropic responses, keyed by an id chosen per-test (see
  # `use_llm_cache(id)`). One file per test: `<cache_root>/cached_calls/<suite>/<id>.yaml`.
  # All calls a test makes land in that one file under `calls:`, each tagged with a
  # `hash` of the kwargs so we can look up the right cached response on replay.
  #
  # YAML shape:
  #   test_suite:    <derived from the spec file path>
  #   test_name:     <full RSpec description>
  #   summary:       <human-readable counts: total / tool_use / message-only>
  #   calls:
  #     - provider:      <which registered adapter produced this — e.g. anthropic>
  #       hash:          <12-char fingerprint of kwargs — used for lookup>
  #       prompt:        <adapter-supplied readable prompt, when present>
  #       payload:       <full canonicalized kwargs — for a precise diff on miss>
  #       response:      <adapter-serialized response hash; the adapter replays it>
  #
  # Behavior:
  #   DISABLE_LLM_CACHE=1     → bypass cache entirely
  #   cache hit               → return cached response
  #   miss + ALLOW_LLM_CALL=1 → call live, append to the test's file
  #   miss + no ALLOW_LLM_CALL → raise Deja::MissingCacheError
  module Cache
    module_function

    def cache_dir
      Deja.configuration.cache_root.join("cached_calls")
    end

    def fetch(method, kwargs, provider:, prompt: nil)
      return yield if ENV["DISABLE_LLM_CACHE"]

      hash = call_hash(method, kwargs)
      record_touched(hash)
      entry = load_call(hash)

      if entry
        response_from_entry(entry)
      elsif ENV["ALLOW_LLM_CALL"]
        response = yield
        append_call!(provider, hash, kwargs, prompt, response)
        response
      else
        raise Deja::MissingCacheError, build_miss_message(hash, kwargs)
      end
    end

    # Builds the MissingCacheError body. When there's a cached entry whose
    # canonicalized payload is similar to the current request, we show a
    # unified diff against the cached payload so the test author can see
    # exactly what drifted between record and replay. The cache stores the
    # full canonicalized payload on each entry, so this covers `system`,
    # `messages`, `tools`, `tool_choice`, etc. — anything the hash is computed
    # over.
    def build_miss_message(hash, kwargs)
      base = "No cached LLM response with hash #{hash} in #{display_path(cache_file)}.\n" \
             "Set ALLOW_LLM_CALL=1 to make the call and record it."
      current_payload = JSON.pretty_generate(cache_affecting_args(kwargs))
      closest = closest_cached_entry(current_payload)
      return base unless closest

      cached_payload = JSON.pretty_generate(closest["payload"]) if closest["payload"]
      cached_payload ||= closest["prompt"].to_s # legacy entries: only prompt was stored
      diff = unified_diff(cached_payload, current_payload, context: 3)
      if diff.empty?
        return "#{base}\n\nClosest cached entry: #{closest['hash']} " \
          "(prompts differ outside the captured payload)"
      end

      "#{base}\n\n" \
        "Closest cached entry: #{closest['hash']}\n" \
        "--- cached payload (#{closest['hash']})\n" \
        "+++ current payload (#{hash})\n" \
        "#{diff}"
    end

    # Picks the cached entry whose stored payload (or, for legacy entries that
    # only stored `prompt`, system text) has the largest LCS overlap with the
    # current request. Returns nil when the cache file is empty.
    def closest_cached_entry(current_text)
      return nil unless cache_file.exist?

      data = YAML.safe_load(cache_file.read, permitted_classes: [], aliases: false)
      calls = data["calls"]
      return nil if calls.nil? || calls.empty?

      current_lines = current_text.lines
      calls.max_by do |c|
        cached_text = c["payload"] ? JSON.pretty_generate(c["payload"]) : c["prompt"].to_s
        Diff::LCS.lcs(cached_text.lines, current_lines).size
      end
    end

    # Returns a unified diff (with `context` lines of context) between two
    # strings, or an empty string when they're identical.
    def unified_diff(old_text, new_text, context: 2)
      old_lines = old_text.lines
      new_lines = new_text.lines
      return "" if old_lines == new_lines

      diffs = Diff::LCS.diff(old_lines, new_lines)
      return "" if diffs.empty?

      out = +""
      file_length_difference = 0
      diffs.each do |piece|
        hunk = Diff::LCS::Hunk.new(old_lines, new_lines, piece, context, file_length_difference)
        file_length_difference = hunk.file_length_difference
        out << hunk.diff(:unified).to_s
        out << "\n"
      end
      out
    end

    # Drops any call entry from the test's file whose hash wasn't looked up during
    # the example — covers the case where a kwarg edit (or a deleted call) leaves
    # an old entry unreachable. Only runs when ALLOW_LLM_CALL=1 (re-record mode);
    # cache-only runs leave the file untouched so a temporarily-disabled call
    # doesn't lose its cached response.
    def prune_untouched_in_current_example!
      return unless cache_file.exist?

      data = YAML.safe_load(cache_file.read)
      touched = touched_hashes
      fresh_calls = data["calls"].select {|c| touched.include?(c["hash"]) }
      return if fresh_calls.size == data["calls"].size

      if fresh_calls.empty?
        cache_file.delete
      else
        data["calls"] = fresh_calls
        data["summary"] = build_summary(fresh_calls)
        cache_file.write(YAML.dump(stringify(data)))
      end
    end

    def record_touched(hash)
      touched_hashes << hash
    end

    def touched_hashes
      current_example!.metadata[:touched_llm_cache_hashes] ||= Set.new
    end

    def cache_file
      cache_dir.join(test_suite, "#{current_id!}.yaml")
    end

    def call_hash(method, kwargs)
      payload = canonicalize({method: method.to_s, args: cache_affecting_args(kwargs)})
      Digest::SHA256.hexdigest(JSON.generate(payload))[0, 12]
    end

    def cache_affecting_args(kwargs)
      canonicalize(kwargs.except(:request_options))
    end

    def canonicalize(obj)
      case obj
      when Hash
        obj.each_with_object({}) {|(k, v), h| h[k.to_s] = canonicalize(v) }.sort.to_h
      when Array
        obj.map {|v| canonicalize(v) }
      when Symbol
        obj.to_s
      else
        obj
      end
    end

    def load_call(hash)
      return nil unless cache_file.exist?

      data = YAML.safe_load(cache_file.read, permitted_classes: [], aliases: false)
      data["calls"].find {|c| c["hash"] == hash }
    end

    # The recorded response hash, handed back to the adapter to deserialize.
    def response_from_entry(entry)
      entry.fetch("response")
    end

    def append_call!(provider, hash, kwargs, prompt, response)
      FileUtils.mkdir_p(cache_file.dirname)
      data = cache_file.exist? ? YAML.safe_load(cache_file.read) : new_file_data
      data["calls"] << build_call_entry(provider, hash, kwargs, prompt, response)
      data["summary"] = build_summary(data["calls"])
      cache_file.write(YAML.dump(stringify(data)))
    end

    def new_file_data
      {
        "test_suite" => test_suite,
        "test_name" => current_test_name,
        "summary" => "",
        "calls" => [],
      }
    end

    # Provider-agnostic: the adapter already serialized `response` (including any
    # readable conveniences like text_response/tool_uses). We tag the entry with
    # the provider and store the canonicalized payload so a cache miss can report
    # a precise diff.
    def build_call_entry(provider, hash, kwargs, prompt, response)
      entry = {"provider" => provider.to_s, "hash" => hash}
      entry["prompt"] = prompt unless prompt.nil?
      entry["payload"] = cache_affecting_args(kwargs)
      entry["response"] = response
      entry
    end

    def build_summary(calls)
      tool_use_count = calls.count {|c| c["response"]["tool_uses"] }
      text_only_count = calls.count {|c| c["response"]["text_response"] && !c["response"]["tool_uses"] }

      parts = [ "#{calls.size} LLM #{calls.size == 1 ? 'call' : 'calls'} made." ]
      if tool_use_count > 0
        parts << "#{tool_use_count} #{tool_use_count == 1 ? 'call' : 'calls'} returned tool use responses."
      end
      if text_only_count > 0
        parts << "#{text_only_count} #{text_only_count == 1 ? 'call' : 'calls'} returned a message response."
      end
      parts.join("\n")
    end

    # Like canonicalize but preserves insertion order so the readable header
    # (test_suite/test_name/summary/calls) stays at the top of the YAML file.
    def stringify(obj)
      case obj
      when Hash
        obj.each_with_object({}) {|(k, v), h| h[k.to_s] = stringify(v) }
      when Array
        obj.map {|v| stringify(v) }
      when Symbol
        obj.to_s
      else
        obj
      end
    end

    # Derived from the spec file path. Purely organizational — moving a test to a
    # different suite means moving its cache file, but the suite name itself has
    # no behavioral effect beyond placement.
    def test_suite
      file_path = current_example!.metadata.fetch(:file_path)
      file_path.sub(%r{^\./spec/}, "").sub(/\.rb$/, "")
    end

    def current_test_name
      current_example!.metadata.fetch(:full_description)
    end

    def current_id!
      id = current_example!.metadata[:llm_cache_id]
      raise Deja::MissingIdError, "No id set on the current example. Call use_llm_cache(id) before making LLM calls." if id.nil?

      id
    end

    def current_example!
      RSpec.current_example or raise Deja::Error, "Deja must be used inside an RSpec example"
    end

    # Renders `path` relative to the configured project_root for friendlier error
    # messages, falling back to the absolute path when it's outside the root.
    def display_path(path)
      path.relative_path_from(Deja.configuration.project_root)
    rescue ArgumentError
      path
    end
  end
end
