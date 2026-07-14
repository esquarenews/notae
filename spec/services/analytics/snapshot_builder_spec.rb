require "rails_helper"

RSpec.describe Analytics::SnapshotBuilder do
  include ActiveSupport::Testing::TimeHelpers

  it "builds personal workspace and app-wide snapshots without leaking other users or workspaces" do
    Time.use_zone("Australia/Melbourne") do
      travel_to Time.zone.parse("2026-07-13 12:00:00") do
        user = User.create!(email: "analytics-snapshot@example.com", password: "password123", time_zone: "Australia/Melbourne")
        other_user = User.create!(email: "analytics-snapshot-other@example.com", password: "password123")
        first = Workspace.create!(name: "Alpha Studio", slug: "alpha-studio")
        second = Workspace.create!(name: "Beta Studio", slug: "beta-studio")
        hidden = Workspace.create!(name: "Hidden Studio", slug: "hidden-studio")
        Membership.create!(user: user, workspace: first, role: :member)
        Membership.create!(user: user, workspace: second, role: :member)
        Membership.create!(user: other_user, workspace: hidden, role: :owner)

        create_activity(user: user, workspace: first, surface: "nota", at: Time.utc(2026, 7, 12, 23, 45), seconds: 30)
        create_activity(user: user, workspace: second, surface: "grid", at: Time.utc(2026, 7, 13, 0, 0), seconds: 20)
        create_activity(user: user, workspace: nil, surface: "home", at: Time.utc(2026, 7, 13, 0, 1), seconds: 10)
        create_activity(user: user, workspace: hidden, surface: "ai", at: Time.utc(2026, 7, 13, 0, 2), seconds: 30)

        Page.create!(workspace: first, created_by: user, title: "My Nota")
        Page.create!(workspace: first, created_by: other_user, title: "Someone else's Nota")
        Database.create!(workspace: second, created_by: user, name: "My Grid")
        Comment.create!(workspace: first, author: user, commentable: Page.first, body: "Useful comment")
        AiConversation.create!(workspace: first, user: user, prompt: "Summarise", answer: "Done", scope: "workspace", model: "gpt-5-mini")
        Page.create!(workspace: hidden, created_by: user, title: "Revoked hidden Nota")
        AiConversation.create!(workspace: hidden, user: user, prompt: "Hidden", answer: "Hidden", scope: "workspace", model: "gpt-5")
        AiUsageLog.create!(
          workspace: first,
          user: user,
          operation: AiUsageLog::OP_ASSISTANT_WRITE,
          model: "gpt-5-mini",
          prompt_tokens: 60,
          completion_tokens: 40,
          total_tokens: 100,
          estimated_cost_usd: 0
        )
        AiUsageLog.create!(
          workspace: hidden,
          user: user,
          operation: AiUsageLog::OP_ASSISTANT_QUERY,
          model: "gpt-5",
          prompt_tokens: 70,
          completion_tokens: 30,
          total_tokens: 100,
          estimated_cost_usd: 0
        )
        AiUsageLog.create!(
          workspace: first,
          user: user,
          operation: AiUsageLog::OP_KNOWLEDGE_SUGGESTION_MISS,
          model: "gpt-5-mini",
          prompt_tokens: 0,
          completion_tokens: 0,
          total_tokens: 0,
          estimated_cost_usd: 0
        )
        WorkflowRun.create!(
          workspace: first,
          user: user,
          workflow_kind: WorkflowRun::KIND_CREATE_NOTA,
          status: WorkflowRun::STATUS_SUCCEEDED,
          trigger_source: "ai_assistant",
          queued_at: Time.current,
          finished_at: Time.current
        )

        date_range = Analytics::DateRange.new(params: { period: "7d" }, today: Time.zone.today)
        workspace_snapshot = described_class.call(user: user, workspaces: [ first ], scope: "workspace", date_range: date_range)
        all_snapshot = described_class.call(user: user, workspaces: [ first, second ], scope: "all", date_range: date_range)

        expect(workspace_snapshot.active_seconds).to eq(30)
        expect(workspace_snapshot.daily_activity.last[:date]).to eq(Date.new(2026, 7, 13))
        expect(workspace_snapshot.daily_activity.last[:seconds]).to eq(30)
        expect(workspace_snapshot.surface_breakdown.map { |entry| entry[:surface] }).to eq([ "nota" ])
        expect(workspace_snapshot.content_counts.index_by { |entry| entry[:key] }.dig(:notas_created, :count)).to eq(1)
        expect(workspace_snapshot.ai_summary).to include(requests: 1, tokens: 100, generated_writes: 1, completed_actions: 1)

        expect(all_snapshot.active_seconds).to eq(60)
        expect(all_snapshot.surface_breakdown.map { |entry| entry[:surface] }).to contain_exactly("nota", "grid", "home")
        expect(all_snapshot.workspace_breakdown.map { |entry| entry[:name] }).to contain_exactly(
          "Alpha Studio",
          "Beta Studio",
          "App-wide & account"
        )
        expect(all_snapshot.workspace_breakdown.map { |entry| entry[:name] }).not_to include("Hidden Studio")
        expect(all_snapshot.ai_summary[:requests]).to eq(1)
        expect(all_snapshot.content_counts.index_by { |entry| entry[:key] }.dig(:notas_created, :count)).to eq(1)
      end
    end
  end

  it "caps concurrent tabs while proportionally retaining each workspace and surface" do
    user = User.create!(email: "analytics-concurrency@example.com", password: "password123")
    first = Workspace.create!(name: "Concurrent first", slug: "concurrent-first")
    second = Workspace.create!(name: "Concurrent second", slug: "concurrent-second")
    Membership.create!(user:, workspace: first, role: :member)
    Membership.create!(user:, workspace: second, role: :member)
    started_at = Time.current.beginning_of_minute
    create_activity(user:, workspace: first, surface: "nota", at: started_at, seconds: 30)
    create_activity(user:, workspace: second, surface: "grid", at: started_at, seconds: 30)

    snapshot = described_class.call(
      user:,
      workspaces: [ first, second ],
      scope: "all",
      date_range: Analytics::DateRange.new(params: { period: "7d" })
    )

    expect(snapshot.active_seconds).to eq(30)
    expect(snapshot.surface_breakdown.to_h { |entry| [ entry[:surface], entry[:seconds] ] }).to eq("nota" => 15, "grid" => 15)
    expect(snapshot.workspace_breakdown.to_h { |entry| [ entry[:name], entry[:active_seconds] ] }).to eq(
      "Concurrent first" => 15,
      "Concurrent second" => 15
    )
  end

  it "counts the union of partially overlapping tabs and reconciles integer attribution" do
    user = User.create!(email: "analytics-overlap@example.com", password: "password123")
    first = Workspace.create!(name: "Overlap first", slug: "overlap-first")
    second = Workspace.create!(name: "Overlap second", slug: "overlap-second")
    Membership.create!(user:, workspace: first, role: :member)
    Membership.create!(user:, workspace: second, role: :member)
    started_at = Time.current.beginning_of_minute
    create_activity(user:, workspace: first, surface: "nota", at: started_at, seconds: 10, offset: 5)
    create_activity(user:, workspace: second, surface: "grid", at: started_at, seconds: 11, offset: 5)
    create_activity(user:, workspace: second, surface: "ai", at: started_at, seconds: 10, offset: 20)

    snapshot = described_class.call(
      user:,
      workspaces: [ first, second ],
      scope: "all",
      date_range: Analytics::DateRange.new(params: { period: "7d" })
    )

    expect(snapshot.active_seconds).to eq(21)
    expect(snapshot.surface_breakdown.sum { |entry| entry[:seconds] }).to eq(21)
    expect(snapshot.surface_breakdown.sum { |entry| entry[:percent] }).to be_within(0.1).of(100)
    expect(snapshot.workspace_breakdown.sum { |entry| entry[:active_seconds] }).to eq(21)
  end

  it "does not count a grid's linked page as a separately created Nota" do
    user = User.create!(email: "analytics-linked-grid@example.com", password: "password123")
    workspace = Workspace.create!(name: "Linked grid", slug: "linked-grid")
    Membership.create!(user:, workspace:, role: :member)
    database = Database.create!(workspace:, created_by: user, name: "Project grid")
    Databases::EnsureLinkedPageService.call(database:, actor: user)

    snapshot = described_class.call(
      user:,
      workspaces: [ workspace ],
      scope: "workspace",
      date_range: Analytics::DateRange.new(params: { period: "7d" })
    )
    counts = snapshot.content_counts.index_by { |entry| entry[:key] }

    expect(counts.dig(:notas_created, :count)).to eq(0)
    expect(counts.dig(:grids_created, :count)).to eq(1)
    expect(snapshot.content_total).to eq(1)
    expect(snapshot.workspace_breakdown.first[:items_created]).to eq(1)
  end

  it "groups a 90-day view into Monday-based weekly totals" do
    travel_to Time.zone.parse("2026-07-13 12:00:00 UTC") do
      user = User.create!(email: "analytics-weekly@example.com", password: "password123", time_zone: "UTC")
      workspace = Workspace.create!(name: "Weekly analytics", slug: "weekly-analytics")
      Membership.create!(user:, workspace:, role: :member)
      create_activity(user:, workspace:, surface: "nota", at: Time.utc(2026, 6, 9, 9, 0), seconds: 30)
      create_activity(user:, workspace:, surface: "grid", at: Time.utc(2026, 6, 10, 9, 0), seconds: 20)
      create_activity(user:, workspace:, surface: "ai", at: Time.utc(2026, 6, 16, 9, 0), seconds: 10)

      snapshot = described_class.call(
        user:,
        workspaces: [ workspace ],
        scope: "workspace",
        date_range: Analytics::DateRange.new(params: { period: "90d" }, today: Time.zone.today)
      )
      weeks = snapshot.trend_series.index_by { |entry| entry[:date] }

      expect(snapshot.date_range.grouping).to eq(:week)
      expect(weeks.fetch(Date.new(2026, 6, 8))[:seconds]).to eq(50)
      expect(weeks.fetch(Date.new(2026, 6, 15))[:seconds]).to eq(10)
    end
  end

  it "adds visible day-to-day comparisons to the trend series" do
    travel_to Time.zone.parse("2026-07-13 12:00:00 UTC") do
      user = User.create!(email: "analytics-comparison@example.com", password: "password123", time_zone: "UTC")
      workspace = Workspace.create!(name: "Daily comparison", slug: "daily-comparison")
      Membership.create!(user:, workspace:, role: :member)
      create_activity(user:, workspace:, surface: "nota", at: Time.utc(2026, 7, 11, 9, 0), seconds: 10)
      create_activity(user:, workspace:, surface: "nota", at: Time.utc(2026, 7, 12, 9, 0), seconds: 20)
      create_activity(user:, workspace:, surface: "nota", at: Time.utc(2026, 7, 13, 9, 0), seconds: 10)

      snapshot = described_class.call(
        user:,
        workspaces: [ workspace ],
        scope: "workspace",
        date_range: Analytics::DateRange.new(params: { period: "7d" }, today: Time.zone.today)
      )
      by_date = snapshot.trend_series.index_by { |entry| entry[:date] }

      expect(by_date.fetch(Date.new(2026, 7, 11))).to include(change_direction: :up, change_label: "New", previous_seconds: 0)
      expect(by_date.fetch(Date.new(2026, 7, 12))).to include(change_direction: :up, change_label: "+100%", previous_seconds: 10)
      expect(by_date.fetch(Date.new(2026, 7, 13))).to include(change_direction: :down, change_label: "-50%", previous_seconds: 20)
    end
  end

  def create_activity(user:, workspace:, surface:, at:, seconds:, offset: 0)
    AnalyticsActivityBucket.create!(
      user: user,
      workspace: workspace,
      surface: surface,
      bucket_started_at: at,
      segment_offset_seconds: offset,
      duration_seconds: seconds
    )
  end
end
