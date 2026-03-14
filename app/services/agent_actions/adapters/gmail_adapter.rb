module AgentActions
  module Adapters
    class GmailAdapter < BaseAdapter
      SUPPORTED_DRAFT_TYPES = %w[email_draft].freeze

      def supports_draft_type?(draft_type)
        SUPPORTED_DRAFT_TYPES.include?(draft_type.to_s)
      end

      def dry_run(agent_action)
        payload = agent_action.payload
        DryRunResult.new(
          target_system: "gmail",
          draft_type: agent_action.draft_type,
          dry_run: true,
          summary: "Gmail draft approved for dry-run only. No message was sent.",
          preview: payload.slice("to", "cc", "subject", "body")
        )
      end
    end
  end
end
