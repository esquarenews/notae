module Workflows
  class SafetyEnvelope
    Decision = Struct.new(
      :allowed,
      :role,
      :reasons,
      :allowed_actions,
      :confidence_threshold,
      :retry_limit,
      :kill_switch_enabled,
      :policy_snapshot,
      keyword_init: true
    ) do
      def to_h
        {
          "allowed" => allowed,
          "role" => role,
          "reasons" => Array(reasons),
          "allowed_actions" => Array(allowed_actions),
          "confidence_threshold" => confidence_threshold.to_f,
          "retry_limit" => retry_limit.to_i,
          "kill_switch_enabled" => kill_switch_enabled,
          "policy_snapshot" => policy_snapshot
        }
      end
    end

    def initialize(workspace:, actor:, workflow_kind:, confidence_score:)
      @workspace = workspace
      @actor = actor
      @workflow_kind = workflow_kind.to_s
      @confidence_score = confidence_score.to_f
    end

    def evaluate
      reasons = []
      reasons << "Automation kill switch is active" unless automation_control.enabled?
      reasons << "Workflow kind is unsupported" unless WorkflowRun::KINDS.include?(workflow_kind)
      reasons << "Workspace policy blocks internal automation" unless policy.allow_internal_automation?
      reasons << "Workflow kind is blocked by workspace policy" unless policy.allowed_internal_actions.include?(workflow_kind)
      reasons << "Membership required" if role.nil?
      reasons << "Guests and auditors cannot launch automated workflows" if membership&.guest? || membership&.auditor?
      reasons << "Your role cannot launch automated workflows under workspace policy" if role.present? && !policy.author_roles.include?(role)
      if confidence_score < policy.automation_confidence_threshold.to_f
        reasons << "Confidence score is below the workspace automation threshold"
      end

      Decision.new(
        allowed: reasons.empty?,
        role: role,
        reasons: reasons,
        allowed_actions: policy.allowed_internal_actions,
        confidence_threshold: policy.automation_confidence_threshold,
        retry_limit: policy.automation_retry_limit,
        kill_switch_enabled: automation_control.enabled?,
        policy_snapshot: policy.policy_snapshot
      )
    end

    private

    attr_reader :workspace, :actor, :workflow_kind, :confidence_score

    def membership
      return nil if actor.blank?

      @membership ||= Membership.find_by(user_id: actor.id, workspace_id: workspace.id)
    end

    def role
      membership&.role
    end

    def policy
      @policy ||= workspace.agent_policy || workspace.build_agent_policy
    end

    def automation_control
      @automation_control ||= AutomationControl.current
    end
  end
end
