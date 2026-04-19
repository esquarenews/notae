module AgentActions
  class UpdateService
    class Error < StandardError; end

    def initialize(agent_action:, actor:, attributes:, comment: nil)
      @agent_action = agent_action
      @actor = actor
      @attributes = attributes.deep_symbolize_keys
      @comment = comment.to_s.strip.presence
    end

    def call
      raise Error, "Draft can no longer be edited" unless agent_action.editable?

      decision = policy_decision
      raise Error, decision.reasons.join(", ") unless decision.allowed

      resubmitting = agent_action.changes_requested?
      agent_action.transaction do
        preview_before = AgentActions::PreviewBuilder.new(agent_action).to_h["after"]
        agent_action.update!(
          title: attributes.fetch(:title, agent_action.title),
          payload_json: attributes.fetch(:payload_json, agent_action.payload_json),
          status: resubmitting ? AgentAction::STATUS_PENDING : agent_action.status,
          rejected_by: nil,
          rejected_at: nil,
          policy_evaluation_json: decision.to_h
        )
        agent_action.log_event!(event_type: "policy_evaluated", actor: actor, details: decision.to_h)
        agent_action.log_event!(
          event_type: "draft_updated",
          actor: actor,
          comment: comment,
          details: {
            "title" => agent_action.title,
            "target_system" => agent_action.target_system,
            "draft_type" => agent_action.draft_type,
            "preview_before" => preview_before,
            "preview_after" => AgentActions::PreviewBuilder.new(agent_action).to_h["after"]
          }
        )
        if resubmitting
          agent_action.log_event!(
            event_type: "resubmitted",
            actor: actor,
            comment: comment,
            details: {
              "status" => agent_action.status,
              "target_system" => agent_action.target_system,
              "draft_type" => agent_action.draft_type
            }
          )
          NotificationService.new(agent_action: agent_action, actor: actor).notify_resubmitted!
        end
        agent_action
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    private

    attr_reader :agent_action, :actor, :attributes, :comment

    def policy_decision
      AgentActions::PolicyEngine.new(
        workspace: agent_action.workspace,
        actor: actor,
        target_system: agent_action.target_system,
        draft_type: agent_action.draft_type,
        lifecycle_operation: AgentActions::PolicyEngine::LIFECYCLE_UPDATE,
        proposed_by: agent_action.proposed_by
      ).evaluate
    end
  end
end
