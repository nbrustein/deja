# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Initial extraction from the Forge test suite.
- `use_llm_cache(id)` — record/replay Anthropic `messages.create` and
  `messages.stream` calls to a per-test YAML file.
- `expect_llm_called` and `forbid_calls` helpers.
- `cached_llm_value(id, *path)` reader.
- `meet_requirements(text)` matcher — judge a value against free-text
  requirements once, then cache the verdict.
- Pluggable provider adapters (`Deja::Adapters::Base`), so a suite can mix
  providers. Ships `:anthropic`. `use_llm_cache` installs every registered
  adapter; cache entries are tagged with `provider:`.
- `Deja.configure` with `cache_root`, `register(provider, install:, real_client:)`,
  a dedicated `judge_client`, and judge model/prompt settings.
- Anthropic SDK response structs + serialize/deserialize extracted into the
  `llm_mock_anthropic` gem (on the shared `llm_mock` contract); the Anthropic
  adapter now delegates to it. `Deja::Anthropic::*` is removed — use
  `LlmMock::Anthropic::*` for canned responses.
