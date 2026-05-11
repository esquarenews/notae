require "rails_helper"
require "stringio"

RSpec.describe WorkspaceCoverAsset, type: :model do
  it "requires an attached image for uploaded recent covers" do
    user = User.create!(email: "cover-asset-upload@example.com", password: "password123")
    workspace = Workspace.create!(name: "Cover assets", slug: "cover-assets")

    asset = workspace.cover_assets.build(created_by: user, source_kind: "upload", label: "Uploaded cover")

    expect(asset).not_to be_valid
    expect(asset.errors[:image]).to include("can't be blank")
  end

  it "validates Unsplash attribution fields for remote covers" do
    user = User.create!(email: "cover-asset-unsplash@example.com", password: "password123")
    workspace = Workspace.create!(name: "Remote cover assets", slug: "remote-cover-assets")

    asset = workspace.cover_assets.build(created_by: user, source_kind: "unsplash", label: "Ocean dusk")
    expect(asset).not_to be_valid

    asset.remote_image_url = "https://images.example.test/ocean.jpg"
    asset.artist_name = "Ava Artist"
    asset.artist_url = "https://unsplash.com/@ava"
    asset.source_url = "https://unsplash.com/?utm_source=notae&utm_medium=referral"

    expect(asset).to be_valid
    expect(asset.remote?).to be(true)
    expect(asset.preview_url).to eq("https://images.example.test/ocean.jpg")
    expect(asset.display_source_name).to eq("Unsplash")
  end

  it "exposes attached uploads via the recent picker scope" do
    user = User.create!(email: "cover-asset-scope@example.com", password: "password123")
    workspace = Workspace.create!(name: "Recent cover scope", slug: "recent-cover-scope")
    older = workspace.cover_assets.new(created_by: user, source_kind: "upload", label: "Older cover")
    older.image.attach(io: StringIO.new("old"), filename: "older.png", content_type: "image/png")
    older.save!
    older.update_columns(created_at: 2.minutes.ago, updated_at: 2.minutes.ago)
    newer = workspace.cover_assets.new(created_by: user, source_kind: "upload", label: "Newer cover")
    newer.image.attach(io: StringIO.new("new"), filename: "newer.png", content_type: "image/png")
    newer.save!

    expect(workspace.cover_assets.for_picker(workspace, user)).to eq([ newer, older ])
  end

  it "rejects SVG uploaded recent covers" do
    user = User.create!(email: "cover-asset-svg@example.com", password: "password123")
    workspace = Workspace.create!(name: "Cover assets svg", slug: "cover-assets-svg")
    asset = workspace.cover_assets.build(created_by: user, source_kind: "upload", label: "Unsafe cover")
    asset.image.attach(io: StringIO.new("<svg></svg>"), filename: "unsafe.svg", content_type: "image/svg+xml")

    expect(asset).not_to be_valid
    expect(asset.errors[:image]).to include("must be a PNG, JPEG, GIF, or WebP")
  end
end
