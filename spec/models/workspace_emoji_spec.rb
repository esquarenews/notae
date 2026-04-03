require "rails_helper"
require "stringio"

RSpec.describe WorkspaceEmoji, type: :model do
  it "generates a unique name from the uploaded filename and exposes an icon token" do
    workspace = Workspace.create!(name: "Emoji workspace", slug: "emoji-workspace")
    first_emoji = workspace.custom_emojis.build
    first_emoji.image.attach(io: StringIO.new("fake-png-content"), filename: "spark-icon.png", content_type: "image/png")
    first_emoji.save!

    second_emoji = workspace.custom_emojis.build
    second_emoji.image.attach(io: StringIO.new("fake-png-content"), filename: "spark-icon.png", content_type: "image/png")
    second_emoji.save!

    expect(first_emoji.name).to be_present
    expect(second_emoji.name).to eq("#{first_emoji.name}_2")
    expect(first_emoji.icon_token).to eq(Page.custom_emoji_token(first_emoji.id))
  end
end
