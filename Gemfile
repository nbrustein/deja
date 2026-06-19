# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# Use sibling checkouts when developing the family together; otherwise resolve the
# published gems (e.g. on CI, where only this repo is checked out).
%w[llm_mock llm_mock_anthropic].each do |sibling|
  path = File.expand_path("../#{sibling}", __dir__)
  gem sibling, path: path if Dir.exist?(path)
end
