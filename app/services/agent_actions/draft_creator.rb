module AgentActions
  class DraftCreator
    class Error < StandardError; end

    def initialize(workspace:, actor:, attributes:)
      @workspace = workspace
      @actor = actor
      @attributes = attributes.deep_symbolize_keys
    end

    def call
      decision = policy_decision(lifecycle_operation: PolicyEngine::LIFECYCLE_DRAFT)
      raise Error, decision.reasons.join(", ") unless decision.allowed

      AgentAction.transaction do
        agent_action = AgentAction.create!(
          workspace: workspace,
          user: actor,
          title: attributes.fetch(:title),
          proposed_by: attributes.fetch(:proposed_by, "manual"),
          target_system: attributes.fetch(:target_system),
          draft_type: attributes.fetch(:draft_type),
          payload_json: attributes.fetch(:payload_json, {}),
          policy_evaluation_json: decision.to_h,
          approval_required: decision.approval_required,
          dry_run: decision.dry_run_only,
          metadata_json: attributes.fetch(:metadata_json, {})
        )
        preview_after = AgentActions::PreviewBuilder.new(agent_action).to_h["after"]
        agent_action.log_event!(event_type: "policy_evaluated", actor: actor, details: decision.to_h)
        agent_action.log_event!(
          event_type: "draft_created",
          actor: actor,
          details: {
            "target_system" => agent_action.target_system,
            "draft_type" => agent_action.draft_type,
            "title" => agent_action.title,
            "preview_after" => preview_after
          }
        )
        NotificationService.new(agent_action: agent_action, actor: actor).notify_approval_requested!
        agent_action
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    private

    attr_reader :workspace, :actor, :attributes

    def policy_decision(lifecycle_operation:)
      AgentActions::PolicyEngine.new(
        workspace: workspace,
        actor: actor,
        target_system: attributes.fetch(:target_system),
        draft_type: attributes.fetch(:draft_type),
        lifecycle_operation: lifecycle_operation,
        estimated_cost_usd: attributes.fetch(:estimated_cost_usd, 0.0)
      ).evaluate
    end
  end
end
