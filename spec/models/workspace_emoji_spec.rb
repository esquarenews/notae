require "rails_helper"
require "stringio"

RSpec.describe WorkspaceEmoji, type: :model do
  it "requires a name and exposes an icon token" do
    workspace = Workspace.create!(name: "Emoji workspace", slug: "emoji-workspace")
    emoji = workspace.custom_emojis.build(name: "Spark icon")
    emoji.image.attach(io: StringIO.new("fake-png-content"), filename: "spark-icon.png", content_type: "image/png")

    expect(emoji).to be_valid
    emoji.save!
    expect(emoji.icon_token).to eq(Page.custom_emoji_token(emoji.id))
  end

  it "rejects blank names" do
    workspace = Workspace.create!(name: "Emoji workspace blank", slug: "emoji-workspace-blank")
    emoji = workspace.custom_emojis.build(name: "")
    emoji.image.attach(io: StringIO.new("fake-png-content"), filename: "spark-icon.png", content_type: "image/png")

    expect(emoji).not_to be_valid
    expect(emoji.errors[:name]).to include("can't be blank")
  end

  it "rejects SVG emoji uploads" do
    workspace = Workspace.create!(name: "Emoji workspace svg", slug: "emoji-workspace-svg")
    emoji = workspace.custom_emojis.build(name: "Unsafe")
    emoji.image.attach(io: StringIO.new("<svg></svg>"), filename: "unsafe.svg", content_type: "image/svg+xml")

    expect(emoji).not_to be_valid
    expect(emoji.errors[:image]).to include("must be a PNG, JPEG, GIF, or WebP")
  end
end
