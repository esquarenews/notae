module Meetings
  class ActionProposalService
    def initialize(session:, actor:)
      @session = session
      @actor = actor
    end

    def call
      clear_existing_session_proposals!
      calendar = target_calendar
      return [] if calendar.blank?

      created = []
      normalized_action_items.each do |action_item|
        due_at = parse_due_at(action_item["due_at"])
        next if due_at.blank?

        proposal = KalendariumWriteProposal.create!(
          workspace: session.workspace,
          user: actor,
          proposed_by: "ai_assistant",
          operation: "create",
          status: "pending",
          expires_at: 7.days.from_now,
          payload_json: build_payload(action_item: action_item, due_at: due_at, calendar: calendar)
        )
        created << proposal
      end

      created
    end

    private

    attr_reader :session, :actor

    def clear_existing_session_proposals!
      KalendariumWriteProposal
        .for_workspace(session.workspace)
        .where(user_id: actor.id)
        .where(status: "pending")
        .where("payload_json ->> 'meeting_session_id' = ?", session.id.to_s)
        .delete_all
    end

    def normalized_action_items
      Array(session.action_items_json).filter_map do |item|
        next unless item.is_a?(Hash)

        title = item["title"].to_s.strip
        next if title.blank?

        item
      end
    end

    def target_calendar
      session.kalendarium_event&.kalendarium_calendar ||
        KalendariumCalendar.user_writable.where(workspace_id: session.workspace_id, enabled: true).order(:created_at).first
    end

    def parse_due_at(raw_due_at)
      value = raw_due_at.to_s.strip
      return nil if value.blank?

      Time.zone.parse(value)&.utc
    rescue ArgumentError, TypeError
      nil
    end

    def build_payload(action_item:, due_at:, calendar:)
      end_at = due_at + 30.minutes
      {
        "meeting_session_id" => session.id.to_s,
        "kalendarium_calendar_id" => calendar.id,
        "title" => action_item["title"].to_s.strip,
        "description" => build_description(action_item),
        "starts_at_utc" => due_at.iso8601,
        "ends_at_utc" => end_at.iso8601,
        "all_day" => false,
        "linked_page_id" => session.page_id
      }
    end

    def build_description(action_item)
      parts = []
      parts << "Action extracted from meeting session #{session.id}."
      owner = action_item["owner"].to_s.strip
      parts << "Owner: #{owner}" if owner.present?
      parts.join(" ")
    end
  end
end
