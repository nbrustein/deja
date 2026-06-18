# frozen_string_literal: true

require_relative "lib/deja/version"

Gem::Specification.new do |spec|
  spec.name = "deja"
  spec.version = Deja::VERSION
  spec.authors = [ "Nate Brustein" ]
  spec.email = [ "nate@bidwrangler.com" ]

  spec.summary = "Record real LLM calls once, replay them in tests, and assert on results."
  spec.description = <<~DESC
    Deja records a non-deterministic call (today: an Anthropic LLM call) the first
    time a test makes it and replays the recorded response on every run after that,
    so tests that exercise real model behavior stay fast, offline, and deterministic.
    Ships RSpec helpers (use_llm_cache, expect_llm_called, forbid_calls) and a
    meet_requirements matcher that judges free-text requirements with the model and
    caches the verdict.
  DESC
  spec.homepage = "https://github.com/nbrustein/deja"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
  ]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "diff-lcs", "~> 1.5"

  # RSpec and the Anthropic SDK are how you actually use Deja, but they live in
  # the host app's test setup. They're declared as development dependencies so the
  # gem's own suite can run; consumers bring their own (see README).
  spec.add_development_dependency "anthropic", ">= 1.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
