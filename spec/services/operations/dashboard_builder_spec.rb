require "rails_helper"

RSpec.describe Operations::DashboardBuilder do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    Rails.cache.clear
    example.run
    Rails.cache.clear
  end

  def build_workspace_stack(suffix:)
    user = User.create!(email: "operations-dashboard-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Operations #{suffix}", slug: "operations-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    [ user, workspace ]
  end

  it "builds operational snapshots across queues, sync, push, and meetings" do
    reference_time = Time.zone.parse("2026-04-18 10:30:00")
    travel_to(reference_time) do
      user, workspace = build_workspace_stack(suffix: "full")

      queue_doubles = {
        "default" => instance_double(Sidekiq::Queue, size: 3, latency: 12.4),
        "epistularium_backfill" => instance_double(Sidekiq::Queue, size: 6, latency: 48.1)
      }
      allow(Sidekiq::Queue).to receive(:new) { |name| queue_doubles.fetch(name) }
      allow(Sidekiq::RetrySet).to receive(:new).and_return(instance_double(Sidekiq::RetrySet, size: 2))
      allow(Sidekiq::ScheduledSet).to receive(:new).and_return(instance_double(Sidekiq::ScheduledSet, size: 4))
      allow(Sidekiq::DeadSet).to receive(:new).and_return(instance_double(Sidekiq::DeadSet, size: 1))
      allow(Sidekiq::ProcessSet).to receive(:new).and_return(
        [
          {
            "identity" => "notae-1",
            "hostname" => "worker-1",
            "tag" => "notae",
            "busy" => 2,
            "concurrency" => 5,
            "beat" => reference_time.to_f
          }
        ]
      )

      EpistulariumAccount.create!(
        workspace: workspace,
        owner: user,
        created_by: user,
        provider: "amazon_workmail",
        label: "Ops mailbox",
        provider_username: "ops@example.com",
        provider_password: "workmail-password",
        status: "connected",
        settings_json: {
          "imap_host" => "imap.mail.ap-southeast-2.awsapps.com",
          "last_fresh_sync_at" => 8.minutes.ago(reference_time).iso8601,
          "last_backfill_sync_at" => 2.hours.ago(reference_time).iso8601,
          "sync_started_at" => 2.minutes.ago(reference_time).iso8601
        }
      )

      connection = KalendariumConnection.create!(
        workspace: workspace,
        owner: user,
        created_by: user,
        provider: "ics",
        label: "Ops calendar",
        ics_url: "https://example.com/ops.ics",
        status: "sync_error",
        last_error: "401 from upstream calendar feed"
      )
      2.times do |index|
        KalendariumCalendar.create!(
          workspace: workspace,
          created_by: user,
          kalendarium_connection: connection,
          name: "Calendar #{index + 1}"
        )
      end

      user.web_push_subscriptions.create!(
        endpoint: "https://web.push.apple.com/QH123",
        p256dh: "p256dh-key",
        auth: "auth-key",
        last_error_at: 5.minutes.ago(reference_time),
        last_error_message: "410 Gone"
      )

      active_session = MeetingSession.create!(
        workspace: workspace,
        created_by: user,
        updated_by: user,
        title: "Daily standup",
        capture_mode: "browser_extension",
        provider: "google_meet",
        status: "processing"
      )
      failed_session = MeetingSession.create!(
        workspace: workspace,
        created_by: user,
        updated_by: user,
        title: "Client handoff",
        capture_mode: "online_bot",
        provider: "zoom",
        status: "failed",
        error_message: "Upload timed out"
      )
      MeetingBotRun.create!(
        meeting_session: active_session,
        provider: "google_meet",
        status: "recording",
        last_heartbeat_at: 1.minute.ago(reference_time)
      )
      MeetingBotRun.create!(
        meeting_session: failed_session,
        provider: "zoom",
        status: "failed",
        error_message: "Browser crashed"
      )

      Notification.create!(
        workspace: workspace,
        recipient: user,
        actor: user,
        notification_type: Notification::TYPE_MENTION,
        metadata: {}
      )
      scoped_token = ApiToken.create!(
        user: user,
        name: "Scoped MCP token",
        scopes_json: [ ApiToken::SCOPE_NOTIFICATIONS_WRITE ]
      )
      Notae::RequestPerformanceStore.record!(
        workspace_id: workspace.id,
        sample: {
          action: "WorkspaceHomeController#show",
          path: "/w/#{workspace.slug}",
          total_ms: 642.4,
          sql_queries: 27,
          sql_ms: 118.6,
          status: 200,
          recorded_at: reference_time - 1.minute
        }
      )
      ApiTokenAuditEvent.create!(
        api_token: scoped_token,
        user: user,
        workspace: workspace,
        event_type: "allowed",
        request_method: "POST",
        path: "/api/v1/workspaces/#{workspace.slug}/notifications/codex_completion",
        controller_name: "Api::V1::NotificationsController",
        action_name: "codex_completion",
        http_status: 201,
        required_scopes_json: [ ApiToken::SCOPE_NOTIFICATIONS_WRITE ],
        metadata_json: { token_name: scoped_token.name }
      )

      snapshot = described_class.new(workspace: workspace, user: user, reference_time: reference_time).call

      expect(snapshot.dig(:background_jobs, :available)).to be(true)
      expect(snapshot.dig(:background_jobs, :queues)).to include(hash_including(name: "default", size: 3))
      expect(snapshot.dig(:background_jobs, :retry_count)).to eq(2)
      expect(snapshot.dig(:background_jobs, :busy_threads)).to eq(2)

      expect(snapshot.dig(:request_performance, :sample_count)).to eq(1)
      expect(snapshot.dig(:request_performance, :slow_count)).to eq(1)
      expect(snapshot.dig(:request_performance, :items).first).to include(
        action: "WorkspaceHomeController#show",
        path: "/w/#{workspace.slug}",
        sql_queries: 27,
        status: 200
      )

      expect(snapshot.dig(:api_token_activity, :event_count)).to eq(1)
      expect(snapshot.dig(:api_token_activity, :items).first).to include(
        token_name: "Scoped MCP token",
        event_type: "allowed",
        request_method: "POST",
        http_status: 201
      )

      expect(snapshot.dig(:epistularium_accounts, :counts, :total)).to eq(1)
      expect(snapshot.dig(:epistularium_accounts, :counts, :active_or_queued)).to eq(1)
      expect(snapshot.dig(:epistularium_accounts, :items).first).to include(
        label: "Ops mailbox",
        provider: "amazon_workmail",
        sync_active: true,
        backfill_pending: true
      )

      expect(snapshot.dig(:kalendarium_connections, :counts, :attention_needed)).to eq(1)
      expect(snapshot.dig(:kalendarium_connections, :items).first).to include(
        label: "Ops calendar",
        calendar_count: 2,
        last_error: "401 from upstream calendar feed"
      )

      expect(snapshot.dig(:push_delivery, :subscription_count)).to eq(1)
      expect(snapshot.dig(:push_delivery, :failing_count)).to eq(1)
      expect(snapshot.dig(:push_delivery, :items).first).to include(
        host: "web.push.apple.com",
        status: :failing
      )

      expect(snapshot.dig(:meeting_capture, :active_session_count)).to eq(1)
      expect(snapshot.dig(:meeting_capture, :failed_session_count)).to eq(1)
      expect(snapshot.dig(:meeting_capture, :active_runs).first).to include(
        title: "Daily standup",
        status: "recording"
      )
      expect(snapshot.dig(:meeting_capture, :latest_failed_run)).to include(
        title: "Client handoff",
        error_message: "Browser crashed"
      )
    end
  end

  it "degrades safely when Sidekiq telemetry is unavailable" do
    user, workspace = build_workspace_stack(suffix: "sidekiq-down")
    allow(Sidekiq::Queue).to receive(:new).and_raise(StandardError, "redis unavailable")

    snapshot = described_class.new(workspace: workspace, user: user).call

    expect(snapshot.dig(:background_jobs, :available)).to be(false)
    expect(snapshot.dig(:background_jobs, :error)).to include("redis unavailable")
  end
end
