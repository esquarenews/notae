module AgentActions
  class ExecutionService
    class Error < StandardError; end

    TASK_STATUS_DEFAULT = "not started".freeze
    TASK_ASSIGNEE_KEYWORDS = %w[assignee owner assigned].freeze
    TASK_PROJECT_KEYWORDS = %w[project queue list backlog].freeze
    TASK_DUE_KEYWORDS = %w[due deadline target].freeze
    TASK_NOTES_KEYWORDS = %w[notes note details detail description body summary].freeze

    def initialize(agent_action:, actor:, destination_database_id: nil, destination_calendar_id: nil)
      @agent_action = agent_action
      @actor = actor
      @destination_database_id = destination_database_id.to_s.strip.presence
      @destination_calendar_id = destination_calendar_id.to_s.strip.presence
    end

    def call
      case agent_action.draft_type
      when "nota_draft"
        create_nota!
      when "task_ticket"
        create_task!
      when "calendar_hold"
        create_calendar_event!
      else
        dry_run_result
      end
    end

    private

    attr_reader :agent_action, :actor, :destination_database_id, :destination_calendar_id

    def workspace
      agent_action.workspace
    end

    def payload
      @payload ||= agent_action.payload
    end

    def dry_run_result
      adapter = AgentActions::AdapterRegistry.fetch(agent_action.target_system)
      adapter.dry_run(agent_action).to_h
    rescue AgentActions::AdapterRegistry::Error => error
      raise Error, error.message
    end

    def create_task!
      ensure_internal_action_allowed!("create_task")

      database = selected_database
      title = payload["title"].to_s.strip
      raise Error, "Task title is required." if title.blank?

      row = database.db_rows.create!(workspace: workspace, title: title)
      seed_task_cells!(database: database, row: row)
      row.reload.sync_data_from_cells!

      {
        "dry_run" => false,
        "target_system" => agent_action.target_system,
        "target_type" => "DbRow",
        "target_id" => row.id,
        "url" => Rails.application.routes.url_helpers.database_path(
          workspace_slug: workspace.slug,
          id: database.id,
          anchor: "row_#{row.id}"
        ),
        "summary" => "Created task in #{database.name}.",
        "destination" => {
          "type" => "task_list",
          "id" => database.id,
          "name" => database.name
        },
        "execution_preview" => execution_preview_for_task(row:, database:)
      }
    end

    def create_nota!
      ensure_internal_action_allowed!("create_nota")

      title = payload["title"].to_s.strip
      body = payload["body"].to_s
      raise Error, "Nota title is required." if title.blank?
      raise Error, "Nota content is required." if body.strip.blank?

      page = workspace.pages.create!(
        title: title,
        created_by: actor,
        page_kind: "nota"
      )
      page.blocks.create!(
        workspace: workspace,
        created_by: actor,
        block_type: "paragraph",
        position: Block::POSITION_GAP,
        content_json: {
          "type" => "doc",
          "content" => [
            {
              "type" => "paragraph",
              "content" => [ { "type" => "text", "text" => body } ]
            }
          ]
        }
      )

      {
        "dry_run" => false,
        "target_system" => agent_action.target_system,
        "target_type" => "Page",
        "target_id" => page.id,
        "url" => Rails.application.routes.url_helpers.page_path(
          workspace_slug: workspace.slug,
          id: page.id
        ),
        "summary" => "Created Nota in #{workspace.name}.",
        "destination" => {
          "type" => "workspace",
          "id" => workspace.id,
          "name" => workspace.name
        },
        "execution_preview" => execution_preview_for_nota(page:, body:)
      }
    end

    def create_calendar_event!
      ensure_internal_action_allowed!("create_calendar_event")

      calendar = selected_calendar
      title = payload["title"].to_s.strip
      raise Error, "Event title is required." if title.blank?

      starts_at = parse_time!(payload["starts_at"], label: "Start")
      ends_at = parse_time!(payload["ends_at"], label: "End")
      raise Error, "End time must be after start time." if ends_at <= starts_at

      event = KalendariumEvent.create!(
        workspace: workspace,
        kalendarium_calendar: calendar,
        title: title,
        description: payload["body"].to_s,
        starts_at_utc: starts_at.utc,
        ends_at_utc: ends_at.utc,
        metadata_json: calendar_metadata,
        created_by: actor,
        updated_by: actor,
        reminder_offsets_minutes: [],
        meeting_capture_enabled: false
      )
      queue_calendar_sync!(calendar)

      {
        "dry_run" => false,
        "target_system" => agent_action.target_system,
        "target_type" => "KalendariumEvent",
        "target_id" => event.id,
        "url" => Rails.application.routes.url_helpers.kalendarium_path(
          workspace_slug: workspace.slug,
          view: "day",
          date: event.starts_at_utc.to_date.iso8601,
          anchor: "kalendarium_event_#{event.id}"
        ),
        "summary" => "Created event in #{calendar.name}.",
        "destination" => {
          "type" => "calendar",
          "id" => calendar.id,
          "name" => calendar.name
        },
        "execution_preview" => execution_preview_for_calendar_event(
          event: event,
          calendar: calendar
        )
      }
    end

    def seed_task_cells!(database:, row:)
      database.db_properties.ordered.each do |property|
        value = task_value_for_property(property)
        next if value.blank?

        DbCell.create!(
          workspace: workspace,
          db_row: row,
          db_property: property,
          value_text: value
        )
      end
    end

    def task_value_for_property(property)
      name = property.name.to_s.strip.downcase
      assignee = payload["assignee"].to_s.strip
      project = payload["project"].to_s.strip
      notes = payload["body"].to_s
      due_date = normalized_due_date

      return TASK_STATUS_DEFAULT if property.select? && name == "status"
      return assignee if assignee.present? && task_assignee_property?(name)
      return project if project.present? && task_project_property?(name)
      return due_date if due_date.present? && property.date? && task_due_property?(name)
      return notes if notes.present? && property.text? && task_notes_property?(name)
      return Date.current.iso8601 if property.date? && name == "date created"

      ""
    end

    def normalized_due_date
      return @normalized_due_date if defined?(@normalized_due_date)

      raw_value = payload["due_at"].to_s.strip
      @normalized_due_date =
        if raw_value.blank?
          nil
        else
          Date.parse(raw_value).iso8601
        end
    rescue ArgumentError
      @normalized_due_date = nil
    end

    def task_assignee_property?(name)
      TASK_ASSIGNEE_KEYWORDS.any? { |keyword| name.include?(keyword) }
    end

    def task_project_property?(name)
      TASK_PROJECT_KEYWORDS.any? { |keyword| name.include?(keyword) }
    end

    def task_due_property?(name)
      TASK_DUE_KEYWORDS.any? { |keyword| name.include?(keyword) }
    end

    def task_notes_property?(name)
      TASK_NOTES_KEYWORDS.any? { |keyword| name.include?(keyword) }
    end

    def selected_database
      raise Error, "Select a task list before approving." if destination_database_id.blank?

      @selected_database ||= scoped_databases.find { |database| database.id == destination_database_id } || raise(Error, "Selected task list could not be found.")
    end

    def selected_calendar
      raise Error, "Select a calendar before approving." if destination_calendar_id.blank?

      @selected_calendar ||= scoped_calendars.find { |calendar| calendar.id == destination_calendar_id } || raise(Error, "Selected calendar could not be found.")
    end

    def scoped_databases
      workspace.databases.active.select { |database| Pundit.policy!(actor, database).update? }
    end

    def scoped_calendars
      workspace.kalendarium_calendars.enabled.user_writable.select { |calendar| Pundit.policy!(actor, calendar).update? }
    end

    def parse_time!(raw_value, label:)
      parsed = Time.zone.parse(raw_value.to_s)
      raise Error, "#{label} time must be valid." if parsed.blank?

      parsed
    rescue ArgumentError, TypeError
      raise Error, "#{label} time must be valid."
    end

    def execution_preview_for_task(row:, database:)
      AgentActions::PreviewBuilder.build_preview(
        draft_type: agent_action.draft_type,
        title: row.title,
        payload: {
          "project" => database.name,
          "assignee" => task_preview_value(row:, keywords: TASK_ASSIGNEE_KEYWORDS),
          "due_at" => task_preview_value(row:, keywords: TASK_DUE_KEYWORDS),
          "body" => task_preview_value(row:, keywords: TASK_NOTES_KEYWORDS)
        }
      )
    end

    def execution_preview_for_nota(page:, body:)
      AgentActions::PreviewBuilder.build_preview(
        draft_type: agent_action.draft_type,
        title: page.title,
        payload: {
          "body" => body
        }
      )
    end

    def execution_preview_for_calendar_event(event:, calendar:)
      AgentActions::PreviewBuilder.build_preview(
        draft_type: agent_action.draft_type,
        title: event.title,
        payload: {
          "starts_at" => payload["starts_at"].to_s.strip,
          "ends_at" => payload["ends_at"].to_s.strip,
          "attendees" => Array(payload["attendees"]),
          "body" => event.description
        }
      )
    end

    def task_preview_value(row:, keywords:)
      row.data_json.to_h.each do |key, value|
        next if value.blank?

        return value.to_s if keywords.any? { |keyword| key.to_s.downcase.include?(keyword) }
      end

      nil
    end

    def calendar_metadata
      invitees = Array(payload["attendees"]).map { |value| value.to_s.strip }.reject(&:blank?).uniq
      return {} if invitees.empty?

      {
        "invitees" => invitees.map { |email| { "email" => email } }
      }
    end

    def queue_calendar_sync!(calendar)
      return if calendar.kalendarium_connection.blank?

      Kalendarium::SyncCalendarJob.perform_later(calendar.id)
    rescue StandardError => error
      raise unless Queueing::JobEnqueueSafety.queue_unavailable?(error)

      Rails.logger.warn("Kalendarium sync queue unavailable for calendar=#{calendar.id}: #{error.class}: #{error.message}")
    end

    def ensure_internal_action_allowed!(action_key)
      return if workspace_policy.allowed_internal_actions.include?(action_key)

      raise Error, "Workspace policy blocks #{action_key.humanize.downcase}."
    end

    def workspace_policy
      @workspace_policy ||= workspace.agent_policy || workspace.build_agent_policy
    end
  end
end
