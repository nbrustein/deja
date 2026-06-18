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
- `Deja.configure` with `cache_root`, `install_client`, `build_real_client`, and
  judge model/prompt settings.
