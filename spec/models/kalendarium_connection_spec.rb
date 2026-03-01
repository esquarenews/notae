require "rails_helper"

RSpec.describe KalendariumConnection, type: :model do
  def build_owner_stack(suffix:)
    user = User.create!(email: "kal-connection-model-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Connection Model #{suffix}", slug: "kal-connection-model-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    [ user, workspace ]
  end

  it "normalizes iCloud credentials by trimming and removing whitespace from app-specific passwords" do
    user, workspace = build_owner_stack(suffix: "normalize")

    connection = described_class.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "icloud_caldav",
      label: "iCloud",
      provider_username: " apple@example.com ",
      provider_password: " abcd-efgh-ijkl-mnop \n"
    )

    expect(connection.provider_username).to eq("apple@example.com")
    expect(connection.provider_password).to eq("abcd-efgh-ijkl-mnop")
  end

  it "rejects non-http urls for ICS connections" do
    user, workspace = build_owner_stack(suffix: "ics-url")

    connection = described_class.new(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "ics",
      label: "ICS",
      ics_url: "webcal://calendar.example.com/feed.ics"
    )

    expect(connection).not_to be_valid
    expect(connection.errors.full_messages.join).to include("Ics url must be a valid HTTP(S) URL")
  end

  it "rejects iCloud passwords that are too short to be app-specific passwords" do
    user, workspace = build_owner_stack(suffix: "icloud-short")

    connection = described_class.new(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "icloud_caldav",
      label: "iCloud",
      provider_username: "apple@example.com",
      provider_password: "short-pass"
    )

    expect(connection).not_to be_valid
    expect(connection.errors.full_messages.join).to include("Provider password looks too short for an Apple app-specific password")
  end
end
