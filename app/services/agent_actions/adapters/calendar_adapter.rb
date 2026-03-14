module AgentActions
  module Adapters
    class CalendarAdapter < BaseAdapter
      SUPPORTED_DRAFT_TYPES = %w[calendar_hold].freeze

      def supports_draft_type?(draft_type)
        SUPPORTED_DRAFT_TYPES.include?(draft_type.to_s)
      end

      def dry_run(agent_action)
        payload = agent_action.payload
        DryRunResult.new(
          target_system: "calendar",
          draft_type: agent_action.draft_type,
          dry_run: true,
          summary: "Calendar hold approved for dry-run only. No calendar event was created.",
          preview: payload.slice("title", "starts_at", "ends_at", "attendees", "body")
        )
      end
    end
  end
end
