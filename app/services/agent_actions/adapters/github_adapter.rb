module AgentActions
  module Adapters
    class GithubAdapter < BaseAdapter
      SUPPORTED_DRAFT_TYPES = %w[github_comment_draft task_ticket].freeze

      def supports_draft_type?(draft_type)
        SUPPORTED_DRAFT_TYPES.include?(draft_type.to_s)
      end

      def dry_run(agent_action)
        payload = agent_action.payload
        DryRunResult.new(
          target_system: "github",
          draft_type: agent_action.draft_type,
          dry_run: true,
          summary: "GitHub draft approved for dry-run only. No GitHub write occurred.",
          preview: payload.slice("repository", "target_reference", "project", "title", "body", "assignee", "due_at")
        )
      end
    end
  end
end
