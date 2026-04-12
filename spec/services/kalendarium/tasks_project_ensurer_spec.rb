require "rails_helper"

RSpec.describe Kalendarium::TasksProjectEnsurer do
  def build_stack(suffix:)
    user = User.create!(email: "kal-tasks-ensurer-#{suffix}@example.com", password: "password123", time_zone: "UTC")
    workspace = Workspace.create!(name: "Kal Tasks Ensurer #{suffix}", slug: "kal-tasks-ensurer-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    [ user, workspace ]
  end

  it "creates the default Tasks project with a writable project calendar" do
    user, workspace = build_stack(suffix: "create")

    project = described_class.new(workspace: workspace, actor: user).call

    expect(project.name).to eq("Tasks")
    expect(project.slug).to eq("tasks")
    expect(project.color_hex).to eq("#10B981")
    expect(project.kalendarium_calendar).to be_present
    expect(project.kalendarium_calendar.source_kind).to eq("project")
    expect(project.kalendarium_calendar.enabled).to be(true)
    expect(project.kalendarium_calendar.time_zone).to eq("UTC")
  end

  it "reuses and restores an archived Tasks project instead of creating a duplicate" do
    user, workspace = build_stack(suffix: "restore")
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Tasks",
      color_hex: "#10B981",
      time_zone: "UTC",
      source_kind: "project",
      enabled: false
    )
    project = KalendariumProject.create!(
      workspace: workspace,
      created_by: user,
      kalendarium_calendar: calendar,
      name: "Tasks",
      slug: "tasks",
      color_hex: "#10B981",
      archived_at: Time.current
    )

    result = nil

    expect do
      result = described_class.new(workspace: workspace, actor: user).call
    end.not_to change(KalendariumProject, :count)

    expect(result.id).to eq(project.id)
    expect(result.reload.archived?).to be(false)
    expect(result.kalendarium_calendar_id).to eq(calendar.id)
    expect(calendar.reload.enabled).to be(true)
  end
end
