require "sidekiq/api"

module Operations
  class DashboardBuilder
    QUEUE_NAMES = %w[default epistularium_backfill].freeze
    PUSH_DEVICE_LIMIT = 5
    SESSION_EVENT_LIMIT = 10

    def initialize(workspace:, user:, reference_time: Time.current)
      @workspace = workspace
      @user = user
      @reference_time = reference_time
    end

    def call
      epistularium = epistularium_accounts_snapshot
      kalendarium = kalendarium_connections_snapshot
      push_delivery = push_delivery_snapshot

      {
        background_jobs: background_jobs_snapshot,
        scheduled_tasks: scheduled_tasks_snapshot,
        request_performance: request_performance_snapshot,
        session_authentication: session_authentication_snapshot,
        api_token_activity: api_token_activity_snapshot,
        integration_health: integration_health_snapshot(
          epistularium:,
          kalendarium:,
          push_delivery:
        ),
        epistularium_accounts: epistularium,
        kalendarium_connections: kalendarium,
        push_delivery:,
        meeting_capture: meeting_capture_snapshot
      }
    end

    private

    attr_reader :workspace, :user, :reference_time

    def scheduled_tasks_snapshot
      items = Notae::ScheduledTaskStore.fetch_all(reference_time:)

      {
        counts: {
          total: items.size,
          healthy: items.count { |item| item[:status] == :healthy },
          attention_needed: items.count { |item| %i[failed drifted].include?(item[:status]) },
          never_run: items.count { |item| item[:status] == :never_run }
        },
        latest_success_at: items.map { |item| item[:last_succeeded_at] }.compact.max,
        items: items
      }
    end

    def background_jobs_snapshot
      queues = QUEUE_NAMES.map do |name|
        queue = Sidekiq::Queue.new(name)
        {
          name: name,
          size: queue.size,
          latency: queue.latency
        }
      end

      retry_set = Sidekiq::RetrySet.new
      scheduled_set = Sidekiq::ScheduledSet.new
      dead_set = Sidekiq::DeadSet.new
      processes = Sidekiq::ProcessSet.new.map do |process|
        {
          identity: process["identity"],
          hostname: process["hostname"],
          tag: process["tag"],
          busy: process["busy"].to_i,
          concurrency: process["concurrency"].to_i,
          beat_at: beat_time(process["beat"])
        }
      end

      {
        available: true,
        queues: queues,
        retry_count: retry_set.size,
        scheduled_count: scheduled_set.size,
        dead_count: dead_set.size,
        process_count: processes.size,
        busy_threads: processes.sum { |process| process[:busy] },
        concurrency: processes.sum { |process| process[:concurrency] },
        processes: processes.first(5)
      }
    rescue StandardError => error
      {
        available: false,
        error: "#{error.class}: #{error.message}"
      }
    end

    def epistularium_accounts_snapshot
      accounts = EpistulariumAccount
        .for_workspace(workspace)
        .order(Arel.sql("LOWER(label) ASC"), created_at: :asc)
        .to_a

      items = accounts.map do |account|
        {
          id: account.id,
          label: account.label,
          provider: account.provider,
          enabled: account.enabled?,
          status: account.status,
          last_fresh_sync_at: account.last_fresh_sync_at,
          last_backfill_sync_at: account.last_backfill_sync_at,
          last_synced_at: account.last_synced_at,
          backfill_pending: account.full_backfill_pending?,
          sync_active: account.sync_active?,
          sync_stalled: account.sync_queue_stalled?(stale_after: EpistulariumAccount::DEFAULT_SYNC_ACTIVITY_TIMEOUT),
          fresh_sync_due: account.fresh_sync_due?(at: reference_time),
          last_error: account.last_error.to_s.strip.presence
        }
      end

      {
        counts: {
          total: accounts.size,
          connected: items.count { |item| item[:status] == "connected" },
          attention_needed: items.count { |item| item[:status] == "sync_error" || item[:last_error].present? },
          active_or_queued: items.count { |item| item[:sync_active] },
          stalled: items.count { |item| item[:sync_stalled] }
        },
        items: items
      }
    end

    def request_performance_snapshot
      items = Notae::RequestPerformanceStore.fetch(workspace_id: workspace.id, limit: 10).map do |sample|
        budget = Notae::RequestPerformanceStore.budget_for(action: sample[:action])
        budget_breaches = Notae::RequestPerformanceStore.budget_breaches(sample)

        {
          action: sample[:action],
          path: sample[:path],
          total_ms: sample[:total_ms].to_f,
          sql_queries: sample[:sql_queries].to_i,
          sql_ms: sample[:sql_ms].to_f,
          status: sample[:status].to_i,
          recorded_at: sample[:recorded_at],
          budget: budget,
          budget_breaches: budget_breaches,
          budget_status: budget_breaches.any? ? :over_budget : :healthy
        }
      end

      worst_actions = items
        .group_by { |item| item[:action] }
        .map do |action, action_items|
          {
            action: action,
            sample_count: action_items.size,
            max_total_ms: action_items.map { |item| item[:total_ms] }.max,
            max_sql_queries: action_items.map { |item| item[:sql_queries] }.max,
            latest_recorded_at: action_items.map { |item| item[:recorded_at] }.compact.max,
            budget_breach_count: action_items.count { |item| item[:budget_status] == :over_budget },
            budget_status: action_items.any? { |item| item[:budget_status] == :over_budget } ? :over_budget : :healthy
          }
        end
        .sort_by do |item|
          [
            item[:budget_status] == :over_budget ? 0 : 1,
            -(item[:budget_breach_count] || 0),
            -(item[:max_total_ms] || 0.0),
            -(item[:max_sql_queries] || 0)
          ]
        end
        .first(5)

      {
        sample_count: items.size,
        slow_count: items.count { |item| item[:total_ms] >= Notae::RequestPerformanceStore::SLOW_REQUEST_THRESHOLD_MS },
        budget_breach_count: items.count { |item| item[:budget_status] == :over_budget },
        slowest_total_ms: items.map { |item| item[:total_ms] }.max,
        highest_sql_queries: items.map { |item| item[:sql_queries] }.max,
        latest_recorded_at: items.map { |item| item[:recorded_at] }.compact.max,
        worst_actions: worst_actions,
        items: items
      }
    end

    def api_token_activity_snapshot
      events = ApiTokenAuditEvent
        .where(workspace_id: workspace.id)
        .includes(:api_token, :user)
        .recent_first
        .limit(10)
        .to_a

      {
        event_count: events.size,
        denied_count: events.count { |event| event.event_type == "scope_denied" },
        token_count: events.filter_map(&:api_token_id).uniq.size,
        latest_event_at: events.first&.created_at,
        items: events.map do |event|
          {
            id: event.id,
            event_type: event.event_type,
            token_name: event.api_token.name,
            user_email: event.user.email,
            path: event.path,
            request_method: event.request_method,
            http_status: event.http_status,
            required_scopes: Array(event.required_scopes_json),
            created_at: event.created_at
          }
        end
      }
    end

    def session_authentication_snapshot
      items = Notae::SessionEventStore.fetch(user_id: user.id, limit: SESSION_EVENT_LIMIT)

      {
        event_count: items.size,
        warning_count: items.count { |item| warning_session_reason?(item[:reason]) },
        latest_event_at: items.first&.dig(:recorded_at),
        latest_warning_at: items.find { |item| warning_session_reason?(item[:reason]) }&.dig(:recorded_at),
        items: items
      }
    end

    def kalendarium_connections_snapshot
      connections = KalendariumConnection
        .for_workspace(workspace)
        .order(Arel.sql("LOWER(label) ASC"), created_at: :asc)
        .to_a
      calendars = KalendariumCalendar.where(kalendarium_connection_id: connections.map(&:id)).to_a
      calendars_by_connection = calendars.group_by(&:kalendarium_connection_id)

      items = connections.map do |connection|
        connection_calendars = calendars_by_connection.fetch(connection.id, [])

        {
          id: connection.id,
          label: connection.label,
          provider: connection.provider,
          enabled: connection.enabled?,
          status: connection.status,
          last_synced_at: connection.last_synced_at,
          last_error: connection.last_error.to_s.strip.presence,
          calendar_count: connection_calendars.size,
          writable_calendar_count: connection_calendars.count(&:user_writable?)
        }
      end

      {
        counts: {
          total: connections.size,
          connected: items.count { |item| item[:status] == "connected" },
          attention_needed: items.count { |item| item[:status] == "sync_error" || item[:last_error].present? },
          writable_calendars: items.sum { |item| item[:writable_calendar_count] }
        },
        items: items
      }
    end

    def integration_health_snapshot(epistularium:, kalendarium:, push_delivery:)
      providers = [
        {
          key: :epistularium,
          label: "Email sync",
          status: provider_status(
            total: epistularium.dig(:counts, :total),
            attention: epistularium.dig(:counts, :attention_needed)
          ),
          connection_count: epistularium.dig(:counts, :total),
          attention_count: epistularium.dig(:counts, :attention_needed),
          capability_summary: "Read mailbox import only",
          writable_target_count: 0,
          latest_activity_at: epistularium[:items].map { |item| item[:last_fresh_sync_at] || item[:last_synced_at] }.compact.max
        },
        {
          key: :kalendarium,
          label: "Calendar sync",
          status: provider_status(
            total: kalendarium.dig(:counts, :total),
            attention: kalendarium.dig(:counts, :attention_needed)
          ),
          connection_count: kalendarium.dig(:counts, :total),
          attention_count: kalendarium.dig(:counts, :attention_needed),
          capability_summary: "Read sync with selective write-back",
          writable_target_count: kalendarium.dig(:counts, :writable_calendars),
          latest_activity_at: kalendarium[:items].map { |item| item[:last_synced_at] }.compact.max
        },
        {
          key: :push_delivery,
          label: "Push delivery",
          status: if push_delivery[:subscription_count].to_i <= 0
            :missing
          elsif push_delivery[:failing_count].to_i.positive?
            :attention
          else
            :healthy
          end,
          connection_count: push_delivery[:subscription_count],
          attention_count: push_delivery[:failing_count],
          capability_summary: "Browser/device banner delivery",
          writable_target_count: push_delivery[:subscription_count],
          latest_activity_at: [ push_delivery[:latest_delivery_at], push_delivery[:latest_error_at] ].compact.max
        }
      ]

      {
        counts: {
          total: providers.size,
          healthy: providers.count { |provider| provider[:status] == :healthy },
          attention_needed: providers.count { |provider| provider[:status] == :attention },
          missing: providers.count { |provider| provider[:status] == :missing }
        },
        providers:
      }
    end

    def push_delivery_snapshot
      subscriptions = user.web_push_subscriptions.order(created_at: :desc).to_a
      device_items = subscriptions.first(PUSH_DEVICE_LIMIT).map do |subscription|
        {
          id: subscription.id,
          host: subscription.endpoint_host,
          created_at: subscription.created_at,
          last_delivered_at: subscription.last_delivered_at,
          last_error_at: subscription.last_error_at,
          last_error_message: subscription.last_error_message.to_s.strip.presence,
          status: subscription.delivery_status
        }
      end

      {
        subscription_count: subscriptions.size,
        failing_count: subscriptions.count { |subscription| subscription.delivery_status == :failing },
        latest_delivery_at: subscriptions.map(&:last_delivered_at).compact.max,
        latest_error_at: subscriptions.map(&:last_error_at).compact.max,
        unread_in_app_count: user.notifications.unread.count,
        items: device_items
      }
    end

    def meeting_capture_snapshot
      sessions_scope = MeetingSession.for_workspace(workspace)
      active_sessions = sessions_scope.active.order(updated_at: :desc).limit(5).to_a
      failed_sessions = sessions_scope.where(status: "failed").order(updated_at: :desc).limit(3).to_a
      active_runs = MeetingBotRun
        .joins(:meeting_session)
        .merge(MeetingSession.for_workspace(workspace))
        .active
        .includes(:meeting_session)
        .order(updated_at: :desc)
        .limit(5)
        .to_a
      latest_failed_run = MeetingBotRun
        .joins(:meeting_session)
        .merge(MeetingSession.for_workspace(workspace))
        .where(status: "failed")
        .includes(:meeting_session)
        .order(updated_at: :desc)
        .first

      {
        active_session_count: sessions_scope.active.count,
        failed_session_count: sessions_scope.where(status: "failed").count,
        active_run_count: MeetingBotRun
          .joins(:meeting_session)
          .merge(MeetingSession.for_workspace(workspace))
          .active
          .count,
        active_sessions: active_sessions.map { |session| meeting_session_payload(session) },
        failed_sessions: failed_sessions.map { |session| meeting_session_payload(session) },
        active_runs: active_runs.map do |run|
          {
            id: run.id,
            status: run.status,
            provider: run.provider,
            worker_id: run.worker_id,
            last_heartbeat_at: run.last_heartbeat_at,
            error_message: run.error_message.to_s.strip.presence,
            title: run.meeting_session.title
          }
        end,
        latest_failed_run: latest_failed_run && {
          id: latest_failed_run.id,
          title: latest_failed_run.meeting_session.title,
          status: latest_failed_run.status,
          provider: latest_failed_run.provider,
          error_message: latest_failed_run.error_message.to_s.strip.presence,
          updated_at: latest_failed_run.updated_at
        }
      }
    end

    def warning_session_reason?(reason)
      %w[cookie_session_near_limit cookie_overflow invalid_authenticity_token failed_authentication].include?(reason.to_s)
    end

    def meeting_session_payload(session)
      {
        id: session.id,
        title: session.title,
        status: session.status,
        provider: session.provider,
        capture_mode: session.capture_mode,
        updated_at: session.updated_at,
        error_message: session.error_message.to_s.strip.presence
      }
    end

    def beat_time(raw_value)
      return nil if raw_value.blank?

      Time.zone.at(raw_value.to_f)
    rescue StandardError
      nil
    end

    def provider_status(total:, attention:)
      return :missing if total.to_i <= 0
      return :attention if attention.to_i.positive?

      :healthy
    end

  end
end
