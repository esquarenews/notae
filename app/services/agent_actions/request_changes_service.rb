module AgentActions
  class RequestChangesService
    class Error < StandardError; end

    def initialize(agent_action:, actor:, comment: nil)
      @agent_action = agent_action
      @actor = actor
      @comment = comment.to_s.strip.presence
    end

    def call
      raise Error, "Draft is not awaiting review" unless agent_action.request_changes_allowed?

      decision = policy_decision
      raise Error, decision.reasons.join(", ") unless decision.allowed

      agent_action.transaction do
        agent_action.update!(
          status: AgentAction::STATUS_CHANGES_REQUESTED,
          policy_evaluation_json: decision.to_h
        )
        agent_action.log_event!(event_type: "policy_evaluated", actor: actor, details: decision.to_h)
        agent_action.log_event!(
          event_type: "changes_requested",
          actor: actor,
          comment: comment,
          details: { "status" => agent_action.status }
        )
        NotificationService.new(agent_action: agent_action, actor: actor).notify_changes_requested!(comment: comment)
        agent_action
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    private

    attr_reader :agent_action, :actor, :comment

    def policy_decision
      AgentActions::PolicyEngine.new(
        workspace: agent_action.workspace,
        actor: actor,
        target_system: agent_action.target_system,
        draft_type: agent_action.draft_type,
        lifecycle_operation: AgentActions::PolicyEngine::LIFECYCLE_REQUEST_CHANGES
      ).evaluate
    end
  end
end
