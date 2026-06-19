# frozen_string_literal: true

RSpec.describe Deja::Configuration do
  it "defaults cache_root to <project_root>/spec/support/deja_cache" do
    config = described_class.new
    config.project_root = "/tmp/myproj"
    expect(config.cache_root.to_s).to eq("/tmp/myproj/spec/support/deja_cache")
  end

  it "uses an explicitly set cache_root over the default" do
    config = described_class.new
    config.cache_root = "/custom/cache"
    expect(config.cache_root.to_s).to eq("/custom/cache")
  end
end
