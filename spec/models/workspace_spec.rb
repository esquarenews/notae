require "rails_helper"

RSpec.describe Workspace, type: :model do
  it "requires a unique slug" do
    described_class.create!(name: "Notae", slug: "notae")
    duplicate = described_class.new(name: "Notae Copy", slug: "notae")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:slug]).to include("has already been taken")
  end

  it "supports pg_search by workspace name" do
    described_class.create!(name: "Engineering Wiki", slug: "eng")
    described_class.create!(name: "Product Docs", slug: "product")

    results = described_class.search_by_name("engine")

    expect(results.map(&:slug)).to include("eng")
    expect(results.map(&:slug)).not_to include("product")
  end

  it "normalizes slugs to stable URL format" do
    workspace = described_class.create!(name: "Marketing", slug: "  Marketing Team  ")

    expect(workspace.slug).to eq("marketing-team")
  end
end
