# Deja

Record a real LLM call once, replay the recorded response on every run after
that. Tests that exercise genuine model behavior stay **fast, offline, and
deterministic** — and your CI never needs an API key.

Deja also ships `meet_requirements`, an RSpec matcher that asserts an
LLM-produced value satisfies a free-text description (judged once by the model,
then cached) instead of pinning to a brittle exact string.

> Today Deja targets the [Anthropic](https://github.com/anthropics/anthropic-sdk-ruby)
> Ruby SDK. The cache format and matcher are provider-agnostic; the serialization
> and judge call are the only Anthropic-specific pieces.

## Installation

```ruby
# Gemfile
group :test do
  gem "deja"
  gem "anthropic" # the SDK Deja records; you likely already have it
end
```

## Setup

Require the RSpec integration and configure the two host-specific seams — where
the cache lives, and how to swap your app's client for Deja's caching stub:

```ruby
# spec/support/deja.rb (or spec/rails_helper.rb)
require "deja/rspec"

Deja.configure do |c|
  c.cache_root = Rails.root.join("spec/support/cache")

  # Whatever your app calls to get an Anthropic client. Deja hands you its
  # caching stub; you return it from that accessor for the duration of the test.
  c.install_client { |client| allow(AnthropicClient).to receive(:client).and_return(client) }
end
```

That assumes your app funnels LLM access through a single seam, e.g.:

```ruby
class AnthropicClient
  def self.client
    Anthropic::Client.new(api_key: ENV["CLAUDE_API_KEY"])
  end
end
```

Block accidental network calls in your test setup, but allow the Anthropic host
so recording can reach it:

```ruby
WebMock.disable_net_connect!(allow_localhost: true, allow: ["api.anthropic.com"])
```

## The workflow

```ruby
it "builds a tutoring activity" do
  use_llm_cache("2026-04-30_17-03") # one cache file for this test

  provider.select_activity! # makes LLM calls — routed through Deja

  kwargs = expect_llm_called          # exactly one call happened
  expect(kwargs[:system]).to include("You are a tutor")

  expect(LearningActivity.last.name).to meet_requirements(<<~REQ)
    A short, learner-facing label under 60 characters.
  REQ
end
```

Run it three ways:

```bash
# 1. First run — nothing cached yet:
bundle exec rspec spec/integration/tutor_spec.rb
#    => Deja::MissingCacheError: "Set ALLOW_LLM_CALL=1 to make the call and record it."

# 2. Record — makes the real calls and writes YAML fixtures:
ALLOW_LLM_CALL=1 bundle exec rspec spec/integration/tutor_spec.rb

# 3. Every run after — replays from cache, no network:
bundle exec rspec spec/integration/tutor_spec.rb
```

Commit the YAML files under `cache_root`. They're the recorded fixtures; CI
replays them with no API key.

## DSL reference

| Helper | What it does |
| --- | --- |
| `use_llm_cache(id)` | Installs the caching stub and sets the per-test cache id. Call once at the top of an example. |
| `expect_llm_called` | Asserts exactly one LLM call happened; returns its kwargs. |
| `forbid_calls` | Installs a client that raises on any access — proves a code path never reaches the LLM. |
| `cached_llm_value(id, *path)` | Reads a value out of a recorded YAML file by walking keys/indices. |
| `meet_requirements(text)` | Matcher: asserts a value satisfies free-text requirements (judged once, cached). |

## How it caches

One YAML file per test, keyed by the id you pass to `use_llm_cache`:

```
<cache_root>/cached_calls/<spec/path>/<id>.yaml        # recorded responses
<cache_root>/meets_requirements/<spec/path>/<id>.yaml  # confirmed meet_requirements values
```

Each request is fingerprinted with a 12-char hash of its canonicalized kwargs.
On replay, a miss prints a unified diff against the closest recorded request so
you can see exactly what drifted. Re-recording (`ALLOW_LLM_CALL=1`) prunes any
cached entry the test no longer reaches.

## Environment variables

| Variable | Effect |
| --- | --- |
| `ALLOW_LLM_CALL=1` | Make real calls and record/update the cache. Requires `CLAUDE_API_KEY`. |
| `DISABLE_LLM_CACHE=1` | Bypass the cache entirely and always call live (debugging). |
| `CLAUDE_API_KEY` | Used by the default real-client builder. |

## Configuration

| Setting | Default | Purpose |
| --- | --- | --- |
| `cache_root` | — (required) | Directory for recorded YAML. |
| `install_client { \|client\| ... }` | — (required) | Swap your app's client for Deja's stub. |
| `build_real_client { ... }` | Anthropic client from `CLAUDE_API_KEY` | How to build a live client for recording and the judge. |
| `project_root` | `Dir.pwd` | Base for relative paths in error messages. |
| `judge_model` | `claude-sonnet-4-5` | Model used by `meet_requirements`. |
| `judge_max_tokens` | `512` | Judge call token cap. |
| `judge_system_prompt` | generic | System prompt for the judge. |

## License

MIT — see [LICENSE](LICENSE).
