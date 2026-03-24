module AgentActions
  module Adapters
    class NotaeAdapter < BaseAdapter
      SUPPORTED_DRAFT_TYPES = %w[nota_draft].freeze

      def supports_draft_type?(draft_type)
        SUPPORTED_DRAFT_TYPES.include?(draft_type.to_s)
      end

      def dry_run(agent_action)
        payload = agent_action.payload
        DryRunResult.new(
          target_system: "notae",
          draft_type: agent_action.draft_type,
          dry_run: true,
          summary: "Nota draft approved for dry-run only. No page was created.",
          preview: payload.slice("title", "body")
        )
      end
    end
  end
end
