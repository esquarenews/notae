require "rails_helper"

RSpec.describe Favorite, type: :model do
  it "enforces uniqueness per user and favoritable record" do
    user = User.create!(email: "favorite-model-unique@example.com", password: "password123")
    workspace = Workspace.create!(name: "Favorite model unique", slug: "favorite-model-unique")
    page = Page.create!(workspace: workspace, created_by: user, title: "Unique page")

    described_class.create!(user: user, workspace: workspace, favoritable: page)
    duplicate = described_class.new(user: user, workspace: workspace, favoritable: page)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:favoritable_id]).to include("has already been taken")
  end

  it "requires favoritable records to belong to the same workspace" do
    user = User.create!(email: "favorite-model-workspace@example.com", password: "password123")
    workspace = Workspace.create!(name: "Favorite model A", slug: "favorite-model-a")
    other_workspace = Workspace.create!(name: "Favorite model B", slug: "favorite-model-b")
    page = Page.create!(workspace: other_workspace, created_by: user, title: "Other workspace page")

    favorite = described_class.new(user: user, workspace: workspace, favoritable: page)

    expect(favorite).not_to be_valid
    expect(favorite.errors[:workspace_id]).to include("must match favoritable workspace")
  end
end
