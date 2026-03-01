require "rails_helper"

RSpec.describe KalendariumProject, type: :model do
  def build_workspace_stack(suffix:)
    user = User.create!(email: "kal-project-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Kal Project #{suffix}", slug: "kal-project-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Projects",
      color_hex: "#8B5CF6",
      time_zone: "UTC",
      source_kind: "project"
    )

    [ user, workspace, calendar ]
  end

  it "defaults and normalizes slug from name" do
    user, workspace, calendar = build_workspace_stack(suffix: "slug")

    project = described_class.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_calendar: calendar,
      name: "Roadmap Launch 2026",
      color_hex: "#8B5CF6"
    )

    expect(project.slug).to eq("roadmap-launch-2026")
  end

  it "normalizes user-entered slug with uppercase and symbols" do
    user, workspace, calendar = build_workspace_stack(suffix: "normalize")

    project = described_class.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_calendar: calendar,
      name: "Ops",
      slug: "  BIG Plan!!  ",
      color_hex: "#8B5CF6"
    )

    expect(project.slug).to eq("big-plan")
  end
end
