module AgentActions
  class PolicyEngine
    ROLE_MEMBER = "member".freeze
    ROLE_ADMIN = "admin".freeze
    ROLE_OWNER = "owner".freeze
    ROLE_GUEST = "guest".freeze
    ROLE_AUDITOR = "auditor".freeze
    ROLE_AUTOMATION_AGENT = "automation_agent".freeze
    ROLE_OPTIONS = [
      ROLE_MEMBER,
      ROLE_ADMIN,
      ROLE_OWNER,
      ROLE_GUEST,
      ROLE_AUDITOR,
      ROLE_AUTOMATION_AGENT
    ].freeze

    LIFECYCLE_DRAFT = "draft".freeze
    LIFECYCLE_UPDATE = "update".freeze
    LIFECYCLE_APPROVE = "approve".freeze
    LIFECYCLE_REJECT = "reject".freeze
    LIFECYCLE_REQUEST_CHANGES = "request_changes".freeze
    LIFECYCLE_OPTIONS = [
      LIFECYCLE_DRAFT,
      LIFECYCLE_UPDATE,
      LIFECYCLE_APPROVE,
      LIFECYCLE_REJECT,
      LIFECYCLE_REQUEST_CHANGES
    ].freeze

    Decision = Struct.new(
      :allowed,
      :role,
      :policy_id,
      :approval_required,
      :dry_run_only,
      :estimated_cost_usd,
      :max_estimated_cost_usd,
      :reasons,
      :allowed_systems,
      :allowed_draft_types,
      :allowed_lifecycle_operations,
      :lifecycle_operation,
      :safety_overrides,
      :policy_snapshot,
      keyword_init: true
    ) do
      def to_h
        {
          "allowed" => allowed,
          "role" => role,
          "policy_id" => policy_id,
          "approval_required" => approval_required,
          "dry_run_only" => dry_run_only,
          "estimated_cost_usd" => estimated_cost_usd.to_f,
          "max_estimated_cost_usd" => max_estimated_cost_usd.to_f,
          "reasons" => Array(reasons),
          "allowed_systems" => Array(allowed_systems),
          "allowed_draft_types" => Array(allowed_draft_types),
          "allowed_lifecycle_operations" => Array(allowed_lifecycle_operations),
          "lifecycle_operation" => lifecycle_operation,
          "safety_overrides" => Array(safety_overrides),
          "policy_snapshot" => policy_snapshot
        }
      end
    end

    SHARED_WORKSPACE_APPROVAL_OVERRIDE = "Shared workspaces always require approval for agent-authored internal writes".freeze
    INTERNAL_WRITE_DRAFT_TYPES = %w[nota_draft task_ticket calendar_hold].freeze

    def initialize(
      workspace:,
      actor:,
      target_system:,
      draft_type:,
      lifecycle_operation:,
      actor_role_override: nil,
      estimated_cost_usd: 0.0,
      proposed_by: "manual"
    )
      @workspace = workspace
      @actor = actor
      @target_system = target_system.to_s
      @draft_type = draft_type.to_s
      @lifecycle_operation = lifecycle_operation.to_s
      @actor_role_override = actor_role_override
      @estimated_cost_usd = estimated_cost_usd.to_f
      @proposed_by = proposed_by.to_s.presence || "manual"
    end

    def evaluate
      active_policy = policy
      reasons = []
      role = resolved_role
      approval_required = active_policy.approval_required_for_draft_type?(draft_type)
      safety_overrides = []

      reasons << "Unsupported target system" unless Search::AssistantQueryService::SUPPORTED_DRAFT_TARGETS.include?(target_system)
      reasons << "Unsupported draft type" unless AgentAction::DRAFT_TYPE_OPTIONS.include?(draft_type)
      reasons << "Unsupported lifecycle operation" unless LIFECYCLE_OPTIONS.include?(lifecycle_operation)
      reasons << "Membership required" if role.nil?
      reasons << "Auditors are read-only" if role == ROLE_AUDITOR && LIFECYCLE_OPTIONS.include?(lifecycle_operation)
      reasons << "Guests cannot manage external action drafts" if role == ROLE_GUEST
      reasons << "Target system is blocked by workspace policy" unless active_policy.allowed_target_systems.include?(target_system)
      reasons << "Draft type is blocked by workspace policy" unless active_policy.allowed_draft_types.include?(draft_type)
      reasons << "Lifecycle operation is blocked by workspace policy" unless active_policy.allowed_lifecycle_operations.include?(lifecycle_operation)
      reasons << "Adapter does not support this draft type" unless adapter_supports_draft_type?
      if role.present? && !active_policy.role_allowed_for_operation?(role, lifecycle_operation)
        reasons << "Your role cannot perform this action under workspace policy"
      end
      if active_policy.max_estimated_cost_usd.to_f.positive? && estimated_cost_usd > active_policy.max_estimated_cost_usd.to_f
        reasons << "Estimated cost exceeds workspace policy"
      end
      if shared_workspace_requires_approval_override?(approval_required:)
        approval_required = true
        safety_overrides << SHARED_WORKSPACE_APPROVAL_OVERRIDE
      end

      Decision.new(
        allowed: reasons.empty?,
        role: role,
        policy_id: active_policy.id,
        approval_required: approval_required,
        dry_run_only: active_policy.dry_run_required?,
        estimated_cost_usd: estimated_cost_usd,
        max_estimated_cost_usd: active_policy.max_estimated_cost_usd,
        reasons: reasons,
        allowed_systems: active_policy.allowed_target_systems,
        allowed_draft_types: active_policy.allowed_draft_types,
        allowed_lifecycle_operations: active_policy.allowed_lifecycle_operations,
        lifecycle_operation: lifecycle_operation,
        safety_overrides: safety_overrides,
        policy_snapshot: active_policy.policy_snapshot.merge(
          "effective_approval_required" => approval_required,
          "safety_overrides" => safety_overrides
        )
      )
    end

    private

    attr_reader :workspace, :actor, :target_system, :draft_type, :lifecycle_operation, :actor_role_override, :estimated_cost_usd, :proposed_by

    def resolved_role
      return actor_role_override if actor_role_override.present?
      return ROLE_AUTOMATION_AGENT if actor.blank?
      return nil if membership.blank?

      membership.role
    end

    def membership
      return nil if actor.blank?

      @membership ||= Membership.find_by(user_id: actor.id, workspace_id: workspace.id)
    end

    def policy
      return @policy if defined?(@policy)

      @policy =
        if workspace.respond_to?(:agent_policy) && ActiveRecord::Base.connection.data_source_exists?("agent_policies")
          workspace.agent_policy || workspace.build_agent_policy
        else
          AgentPolicy.new(workspace: workspace)
        end
    rescue ActiveRecord::StatementInvalid
      @policy = AgentPolicy.new(workspace: workspace)
    end

    def adapter_supports_draft_type?
      adapter = AgentActions::AdapterRegistry.fetch(target_system)
      adapter.supports_draft_type?(draft_type)
    rescue AgentActions::AdapterRegistry::Error
      false
    end

    def shared_workspace_requires_approval_override?(approval_required:)
      return false if approval_required
      return false unless lifecycle_operation == LIFECYCLE_DRAFT
      return false unless INTERNAL_WRITE_DRAFT_TYPES.include?(draft_type)
      return false unless proposed_by != "manual"
      return false unless shared_workspace?

      true
    end

    def shared_workspace?
      human_memberships_count > 1
    end

    def human_memberships_count
      @human_memberships_count ||= workspace.memberships.where.not(role: Membership.roles[:automation_agent]).count
    end
  end
end
