require "rails_helper"

RSpec.describe Notae::SolidCacheSupport do
  describe ".session_store" do
    it "returns cookie_store in test" do
      expect(described_class.session_store).to eq(:cookie_store)
    end
  end

  describe ".cache_store" do
    around do |example|
      original_env = ENV["NOTAE_SOLID_CACHE"]
      ENV["NOTAE_SOLID_CACHE"] = env_value
      example.run
    ensure
      ENV["NOTAE_SOLID_CACHE"] = original_env
    end

    let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
    let(:env_value) { "true" }

    before do
      allow(Rails.env).to receive(:test?).and_return(false)
      allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
    end

    it "uses Solid Cache when requested and available" do
      allow(connection).to receive(:data_source_exists?).with("solid_cache_entries").and_return(true)

      expect(described_class.cache_store).to eq(:solid_cache_store)
      expect(described_class.session_store).to eq(:cache_store)
    end

    it "falls back when the Solid Cache table is missing" do
      allow(connection).to receive(:data_source_exists?).with("solid_cache_entries").and_return(false)

      expect(described_class.cache_store).to eq(:memory_store)
      expect(described_class.session_store).to eq(:cookie_store)
    end

    it "falls back when Solid Cache is disabled by environment" do
      allow(connection).to receive(:data_source_exists?).with("solid_cache_entries").and_return(true)
      ENV["NOTAE_SOLID_CACHE"] = "false"

      expect(described_class.cache_store).to eq(:memory_store)
      expect(described_class.session_store).to eq(:cookie_store)
    end

    it "falls back when checking the cache table raises" do
      allow(connection).to receive(:data_source_exists?).with("solid_cache_entries").and_raise(ActiveRecord::StatementInvalid.new("boom"))

      expect(described_class.cache_store).to eq(:memory_store)
      expect(described_class.session_store).to eq(:cookie_store)
    end
  end
end
