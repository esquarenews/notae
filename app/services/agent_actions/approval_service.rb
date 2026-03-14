module AgentActions
  class ApprovalService
    class Error < StandardError; end

    def initialize(agent_action:, actor:, comment: nil)
      @agent_action = agent_action
      @actor = actor
      @comment = comment.to_s.strip.presence
    end

    def call
      raise Error, "Draft is not awaiting approval" unless agent_action.approvable?

      decision = policy_decision
      raise Error, decision.reasons.join(", ") unless decision.allowed

      adapter = AgentActions::AdapterRegistry.fetch(agent_action.target_system)
      result = adapter.dry_run(agent_action)

      agent_action.transaction do
        agent_action.update!(
          status: AgentAction::STATUS_APPROVED,
          approved_by: actor,
          approved_at: Time.current,
          rejected_by: nil,
          rejected_at: nil,
          executed_at: Time.current,
          result_json: result.to_h,
          policy_evaluation_json: decision.to_h
        )
        agent_action.log_event!(event_type: "policy_evaluated", actor: actor, details: decision.to_h)
        agent_action.log_event!(event_type: "approved", actor: actor, comment: comment, details: { "status" => agent_action.status })
        agent_action.log_event!(event_type: "tool_used", actor: actor, details: result.to_h)
        NotificationService.new(agent_action: agent_action, actor: actor).notify_approved!(comment: comment)
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
        lifecycle_operation: AgentActions::PolicyEngine::LIFECYCLE_APPROVE
      ).evaluate
    end
  end
end
