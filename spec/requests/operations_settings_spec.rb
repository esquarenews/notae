require "rails_helper"

RSpec.describe "Operations settings", type: :request do
  it "renders the operations dashboard and settings navigation entry" do
    user = User.create!(email: "operations-settings@example.com", password: "password123")
    workspace = Workspace.create!(name: "Operations settings", slug: "operations-settings")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    sign_in user

    allow_any_instance_of(Operations::DashboardBuilder).to receive(:call).and_return(
      background_jobs: {
        available: true,
        queues: [
          { name: "default", size: 2, latency: 3.1 },
          { name: "epistularium_backfill", size: 1, latency: 12.5 }
        ],
        retry_count: 0,
        scheduled_count: 1,
        dead_count: 0,
        process_count: 1,
        busy_threads: 1,
        concurrency: 5,
        processes: [
          { hostname: "worker-1", identity: "worker-1", busy: 1, concurrency: 5, beat_at: 2.minutes.ago }
        ]
      },
      scheduled_tasks: {
        counts: {
          total: 6,
          healthy: 1,
          attention_needed: 1,
          never_run: 4
        },
        latest_success_at: 4.minutes.ago,
        items: [
          {
            task_name: "epistularium:sync_due",
            label: "Epistularium sync timer",
            cadence_label: "Every 10 minutes",
            status: :healthy,
            last_started_at: 4.minutes.ago,
            last_succeeded_at: 4.minutes.ago,
            last_failed_at: nil,
            last_duration_ms: 312.5,
            last_error: nil,
            last_error_class: nil,
            consecutive_failures: 0
          },
          {
            task_name: "kalendarium:dispatch_reminders",
            label: "Kalendarium reminder dispatch",
            cadence_label: "Manual or external trigger",
            status: :failed,
            last_started_at: 2.minutes.ago,
            last_succeeded_at: nil,
            last_failed_at: 2.minutes.ago,
            last_duration_ms: 210.0,
            last_error: "redis unavailable",
            last_error_class: "StandardError",
            consecutive_failures: 1
          }
        ]
      },
      session_authentication: {
        event_count: 0,
        warning_count: 0,
        latest_event_at: nil,
        latest_warning_at: nil,
        items: []
      },
      integration_health: {
        counts: {
          total: 3,
          healthy: 1,
          attention_needed: 1,
          missing: 1
        },
        providers: [
          {
            key: :epistularium,
            label: "Email sync",
            status: :healthy,
            connection_count: 1,
            attention_count: 0,
            capability_summary: "Read mailbox import only",
            writable_target_count: 0,
            latest_activity_at: 5.minutes.ago
          },
          {
            key: :kalendarium,
            label: "Calendar sync",
            status: :attention,
            connection_count: 1,
            attention_count: 1,
            capability_summary: "Read sync with selective write-back",
            writable_target_count: 2,
            latest_activity_at: 10.minutes.ago
          },
          {
            key: :push_delivery,
            label: "Push delivery",
            status: :missing,
            connection_count: 0,
            attention_count: 0,
            capability_summary: "Browser/device banner delivery",
            writable_target_count: 0,
            latest_activity_at: nil
          }
        ]
      },
      request_performance: {
        sample_count: 2,
        slow_count: 1,
        budget_breach_count: 1,
        slowest_total_ms: 642.4,
        highest_sql_queries: 27,
        latest_recorded_at: 30.seconds.ago,
        worst_actions: [
          {
            action: "WorkspaceHomeController#show",
            sample_count: 1,
            max_total_ms: 642.4,
            max_sql_queries: 27,
            latest_recorded_at: 30.seconds.ago,
            budget_breach_count: 1,
            budget_status: :over_budget
          }
        ],
        items: [
          {
            action: "WorkspaceHomeController#show",
            path: "/w/#{workspace.slug}",
            total_ms: 642.4,
            sql_queries: 27,
            sql_ms: 118.6,
            status: 200,
            recorded_at: 30.seconds.ago,
            budget: { total_ms: 600.0, sql_queries: 20, sql_ms: 90.0 },
            budget_breaches: [ "total time", "sql queries", "sql time" ],
            budget_status: :over_budget
          }
        ]
      },
      api_token_activity: {
        event_count: 2,
        denied_count: 1,
        token_count: 1,
        latest_event_at: 20.seconds.ago,
        items: [
          {
            token_name: "Scoped MCP token",
            user_email: user.email,
            event_type: "scope_denied",
            path: "/api/v1/workspaces/#{workspace.slug}/notifications/codex_completion",
            request_method: "POST",
            http_status: 403,
            required_scopes: [ "notifications:write" ],
            created_at: 20.seconds.ago
          }
        ]
      },
      epistularium_accounts: {
        counts: { total: 1, connected: 1, attention_needed: 0, active_or_queued: 1, stalled: 0 },
        items: [
          {
            label: "Mailbox",
            provider: "amazon_workmail",
            enabled: true,
            status: "connected",
            last_fresh_sync_at: 5.minutes.ago,
            last_backfill_sync_at: 1.hour.ago,
            last_synced_at: 5.minutes.ago,
            backfill_pending: true,
            sync_active: true,
            sync_stalled: false,
            fresh_sync_due: false,
            last_error: nil
          }
        ]
      },
      kalendarium_connections: {
        counts: { total: 1, connected: 1, attention_needed: 0, writable_calendars: 2 },
        items: [
          {
            label: "Calendar",
            provider: "ics",
            enabled: true,
            status: "connected",
            last_synced_at: 10.minutes.ago,
            last_error: nil,
            calendar_count: 2,
            writable_calendar_count: 2
          }
        ]
      },
      push_delivery: {
        subscription_count: 1,
        failing_count: 0,
        latest_delivery_at: 1.minute.ago,
        latest_error_at: nil,
        unread_in_app_count: 2,
        items: [
          {
            host: "web.push.apple.com",
            created_at: 1.day.ago,
            last_delivered_at: 1.minute.ago,
            last_error_at: nil,
            last_error_message: nil,
            status: :healthy
          }
        ]
      },
      meeting_capture: {
        active_session_count: 1,
        failed_session_count: 0,
        active_run_count: 1,
        active_sessions: [
          {
            title: "Daily standup",
            provider: "google_meet",
            capture_mode: "browser_extension",
            status: "processing",
            updated_at: 3.minutes.ago,
            error_message: nil
          }
        ],
        failed_sessions: [],
        active_runs: [],
        latest_failed_run: nil
      }
    )

    get workspace_operations_settings_path(workspace_slug: workspace.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Operations")
    expect(response.body).to include("Background jobs")
    expect(response.body).to include("Scheduled tasks")
    expect(response.body).to include("Integration health")
    expect(response.body).to include("Read sync with selective write-back")
    expect(response.body).to include("Writable calendars")
    expect(response.body).to include("Epistularium sync timer")
    expect(response.body).to include("Kalendarium reminder dispatch")
    expect(response.body).to include("Recent request performance")
    expect(response.body).to include("Budget breaches")
    expect(response.body).to include("Highest query count")
    expect(response.body).to include("Over budget")
    expect(response.body).to include("API token activity")
    expect(response.body).to include("Scoped MCP token")
    expect(response.body).to include("WorkspaceHomeController#show")
    expect(response.body).to include("Email sync")
    expect(response.body).to include("Calendar connections")
    expect(response.body).to include("Push delivery")
    expect(response.body).to include("Meeting capture")
    expect(response.body).to include(
      ERB::Util.html_escape(
        workspace_operations_settings_path(
          workspace_slug: workspace.slug,
          settings_workspace_slug: workspace.slug
        )
      )
    )
    expect(response.body).not_to include("Operations <em>Future</em>")
  end
end
