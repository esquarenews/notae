module AgentActions
  module Adapters
    class SlackAdapter < BaseAdapter
      SUPPORTED_DRAFT_TYPES = %w[task_ticket].freeze

      def supports_draft_type?(draft_type)
        SUPPORTED_DRAFT_TYPES.include?(draft_type.to_s)
      end

      def dry_run(agent_action)
        payload = agent_action.payload
        DryRunResult.new(
          target_system: "slack",
          draft_type: agent_action.draft_type,
          dry_run: true,
          summary: "Slack handoff draft approved for dry-run only. No Slack message was posted.",
          preview: payload.slice("project", "title", "body", "assignee", "due_at")
        )
      end
    end
  end
end
