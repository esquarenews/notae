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

  it "requires a supported workspace colour and normalizes it" do
    workspace = described_class.create!(
      name: "Colour workspace",
      slug: "colour-workspace",
      workspace_color: Workspace::WORKSPACE_COLOR_OPTIONS.second.fetch(:value).upcase
    )

    expect(workspace.workspace_color).to eq(Workspace::WORKSPACE_COLOR_OPTIONS.second.fetch(:value))
    expect(described_class.new(name: "Invalid colour", slug: "invalid-colour", workspace_color: "#ffffff")).not_to be_valid
  end

  it "normalizes and validates the shell status bar mode" do
    workspace = described_class.create!(
      name: "Shell bar workspace",
      slug: "shell-bar-workspace",
      shell_status_bar_mode: " TIME_ONLY "
    )

    expect(workspace.shell_status_bar_mode).to eq("time_only")
    expect(described_class.new(name: "Invalid bar mode", slug: "invalid-bar-mode", shell_status_bar_mode: "nope")).not_to be_valid
  end

  it "encrypts join link token at rest" do
    workspace = described_class.create!(name: "Join link workspace", slug: "join-link-workspace")

    workspace.ensure_join_link_token!
    plaintext = workspace.join_link_token
    workspace.reload

    expect(workspace.attributes_before_type_cast["join_link_token"]).not_to eq(plaintext)
    expect(workspace.join_link_token).to eq(plaintext)
  end
end
