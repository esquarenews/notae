module AgentActions
  module Adapters
    class CrmAdapter < BaseAdapter
      SUPPORTED_DRAFT_TYPES = %w[task_ticket].freeze

      def supports_draft_type?(draft_type)
        SUPPORTED_DRAFT_TYPES.include?(draft_type.to_s)
      end

      def dry_run(agent_action)
        payload = agent_action.payload
        DryRunResult.new(
          target_system: "crm",
          draft_type: agent_action.draft_type,
          dry_run: true,
          summary: "CRM task draft approved for dry-run only. No CRM record was created.",
          preview: payload.slice("project", "title", "body", "assignee", "due_at")
        )
      end
    end
  end
end
