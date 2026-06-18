# Deja

Deja gives you automated testing tools that allow you to assert on the arguments you are sending to LLM apis and on the responses you are getting from them.

## Overview

### What Deja allows

Deja allows you to add the following coverage to your test.

  * I have application code that generates arguments for an LLM api. I want to assert on the arguments that were provided to the LLM api.
  * When I pass certain arguments (i.e. a certain prompt) to an LLM, the result is non-deterministic. Even so, I have certain requirements
    as to what the result should be. I want to assert that the LLM's response meets those requirements.

With this functionality, you can do the following.

  * I want to change my code and be sure that the changes I made did not affect the arguments passed to the LLM api.
  * I want to iterate on my application code in ways that will change a prompt sent to an LLM until the response meets certain requirements.
  * I want to change my code in a way that will change a prompt sent to an LLM and be sure that the response still meets existing requirements.
  * I want to upgrade to a new model and be sure that all of my existing calls still meet existing requirements.

### How Deja works

  1. You run a test locally with ALLOW_LLM_CALL=1.
    * When your test hits application code that triggers a call to an LLM api, the call is actually made via http.
    * You assert on the arguments that were sent to the LLM api
    * You assert in a fuzzy way on the response, like "The response should say that..."
    * Deja caches the response, keyed off of the exact set of arguments. The cached response is stored in a generated file, which
      you store in version control.
  2. You run the test again
    * When the LLM api call is triggered, the test finds the response in the cache, skipping the http call to the LLM api
    * Your assertions ensure that your code still sent the expected arguments
  3. You push your code and tests run on CI
    * Since the cached response is stored in version control, CI has access to it and runs the test without making any
      actual LLM calls
  4. You update code and re-run the test locally with ALLOW_LLM_CALL=1.
    * The updated code can change the prompt, the LLM model, or anything else that will change the arguments sent to the LLM api.
    * Since there is no cached response for the new arguments, the call to the LLM api is actually made via http.
    * The new response is cached, replacing the old one
    * Your fuzzy assertion ensures that the new response still matches your requirements.

### LLM support

Today Deja targets the [Anthropic](https://github.com/anthropics/anthropic-sdk-ruby). Support for other SDKs is coming.

## Usage

### Installation

```ruby
# Gemfile
group :test do
  gem "deja"
end
```

### Setup

Require the RSpec integration, point Deja at a cache directory, and register a
provider — telling it how to swap your app's client for Deja's caching stub:

```ruby
# spec/support/deja.rb (or spec/rails_helper.rb)
require "deja/rspec"

Deja.configure do |c|
  c.cache_root = Rails.root.join("spec/support/cache")

  # Whatever your app calls to get an Anthropic client. Deja hands you its
  # caching stub; you return it from that accessor for the duration of the test.
  c.register :anthropic,
    install: ->(mock_anthropic_client) { allow(AnthropicClient).to receive(:client).and_return(mock_anthropic_client) }
end
```

That assumes your app funnels LLM access through a single seam. e.g., In this example,
Deja will mock out calls to `AnthropicClient.client`:

```ruby
class AnthropicClient
  def self.client
    Anthropic::Client.new(api_key: ENV["CLAUDE_API_KEY"])
  end
end
```


**Optional:** Deja doesn't require WebMock — it intercepts calls at the client
seam, not at the HTTP layer. But if your suite already uses WebMock, allow the
Anthropic host so recording can reach it (and keep the allowlist tight so a
forgotten stub surfaces as a blocked request rather than a silent live call):

```ruby
WebMock.disable_net_connect!(allow_localhost: true, allow: ["api.anthropic.com"])
```

## The workflow

```ruby
it "summarizes an article" do
  use_llm_cache("2026-04-30_17-03") # one cache file for this test

  summary = ArticleSummarizer.new(article).call # makes LLM calls — routed through Deja

  kwargs = expect_llm_called          # exactly one call happened
  expect(kwargs[:system]).to include("You are a summarization assistant")

  expect(summary).to meet_requirements(<<~REQ)
    A single sentence under 200 characters that indicates that the article is about The Hitchhiker's Guide to the Galaxy
  REQ
end
```

Run it three ways:

```bash
# 1. First run — nothing cached yet:
bundle exec rspec spec/integration/article_summarizer_spec.rb
#    => Deja::MissingCacheError: "Set ALLOW_LLM_CALL=1 to make the call and record it."

# 2. Record — makes the real calls and writes YAML fixtures:
ALLOW_LLM_CALL=1 bundle exec rspec spec/integration/article_summarizer_spec.rb

# 3. Every run after — replays from cache, no network:
bundle exec rspec spec/integration/article_summarizer_spec.rb
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
| `register(provider, install:, real_client:, as:)` | — (≥1 required) | Register a provider. `install` swaps your app's client for Deja's stub; `real_client` (optional) builds a live client for recording. |
| `project_root` | `Dir.pwd` | Base for relative paths in error messages. |
| `judge_client { ... }` | Anthropic client from `CLAUDE_API_KEY` | Live client used by the `meet_requirements` judge. |
| `judge_model` | `claude-sonnet-4-5` | Model used by `meet_requirements`. |
| `judge_max_tokens` | `512` | Judge call token cap. |
| `judge_system_prompt` | generic | System prompt for the judge. |

## License

MIT — see [LICENSE](LICENSE).
