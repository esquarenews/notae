class AgentPolicy < ApplicationRecord
  DEFAULT_AUTHOR_ROLES = %w[member admin owner automation_agent].freeze
  DEFAULT_APPROVER_ROLES = %w[admin owner].freeze
  DEFAULT_MAX_ESTIMATED_COST_USD = 0.0
  INTERNAL_ACTION_OPTIONS = %w[create_nota update_nota create_task create_calendar_event create_database].freeze
  DEFAULT_ALLOWED_INTERNAL_ACTIONS = INTERNAL_ACTION_OPTIONS.freeze
  DEFAULT_AUTOMATION_RETRY_LIMIT = 2
  DEFAULT_AUTOMATION_CONFIDENCE_THRESHOLD = 0.7

  belongs_to :workspace

  validates :approval_required, inclusion: { in: [ true, false ] }
  validates :dry_run_required, inclusion: { in: [ true, false ] }
  validates :allow_internal_automation, inclusion: { in: [ true, false ] }
  validates :max_estimated_cost_usd, numericality: { greater_than_or_equal_to: 0 }
  validates :automation_retry_limit, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :automation_confidence_threshold, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :workspace_id, uniqueness: true
  validate :validate_allowed_target_systems
  validate :validate_allowed_draft_types
  validate :validate_allowed_lifecycle_operations
  validate :validate_author_roles
  validate :validate_approver_roles
  validate :validate_allowed_internal_actions

  before_validation :apply_defaults

  def allowed_target_systems
    normalize_collection(allowed_target_systems_json.presence || default_allowed_target_systems, Search::AssistantQueryService::SUPPORTED_DRAFT_TARGETS)
  end

  def allowed_draft_types
    normalize_collection(allowed_draft_types_json.presence || AgentAction::DRAFT_TYPE_OPTIONS, AgentAction::DRAFT_TYPE_OPTIONS)
  end

  def allowed_lifecycle_operations
    normalize_collection(
      allowed_lifecycle_operations_json.presence || AgentActions::PolicyEngine::LIFECYCLE_OPTIONS,
      AgentActions::PolicyEngine::LIFECYCLE_OPTIONS
    )
  end

  def author_roles
    normalize_collection(author_roles_json.presence || DEFAULT_AUTHOR_ROLES, Membership.roles.keys)
  end

  def approver_roles
    normalize_collection(approver_roles_json.presence || DEFAULT_APPROVER_ROLES, Membership.roles.keys)
  end

  def allowed_internal_actions
    normalize_collection(allowed_internal_actions_json.presence || DEFAULT_ALLOWED_INTERNAL_ACTIONS, INTERNAL_ACTION_OPTIONS)
  end

  def approval_required_draft_types
    normalize_collection(metadata_json.to_h["approval_required_draft_types"], AgentAction::DRAFT_TYPE_OPTIONS)
  end

  def approval_required_draft_types_json
    approval_required_draft_types
  end

  def approval_required_draft_types_json=(values)
    self.metadata_json = metadata_json.to_h.merge(
      "approval_required_draft_types" => normalize_collection(values, AgentAction::DRAFT_TYPE_OPTIONS)
    )
  end

  def approval_required_for_draft_type?(draft_type)
    approval_required? || approval_required_draft_types.include?(draft_type.to_s)
  end

  def role_allowed_for_operation?(role, lifecycle_operation)
    normalized_role = role.to_s
    return false if normalized_role.blank?

    allowed_roles_for(lifecycle_operation).include?(normalized_role)
  end

  def policy_snapshot
    {
      "allowed_target_systems" => allowed_target_systems,
      "allowed_draft_types" => allowed_draft_types,
      "allowed_lifecycle_operations" => allowed_lifecycle_operations,
      "author_roles" => author_roles,
      "approver_roles" => approver_roles,
      "approval_required" => approval_required,
      "approval_required_draft_types" => approval_required_draft_types,
      "dry_run_required" => dry_run_required,
      "max_estimated_cost_usd" => max_estimated_cost_usd.to_f,
      "allow_internal_automation" => allow_internal_automation,
      "allowed_internal_actions" => allowed_internal_actions,
      "automation_retry_limit" => automation_retry_limit,
      "automation_confidence_threshold" => automation_confidence_threshold.to_f,
      "metadata" => metadata_json.to_h
    }
  end

  private

  def apply_defaults
    self.allowed_target_systems_json = default_allowed_target_systems if allowed_target_systems_json.blank?
    self.allowed_draft_types_json = AgentAction::DRAFT_TYPE_OPTIONS if allowed_draft_types_json.blank?
    self.allowed_lifecycle_operations_json = AgentActions::PolicyEngine::LIFECYCLE_OPTIONS if allowed_lifecycle_operations_json.blank?
    self.author_roles_json = DEFAULT_AUTHOR_ROLES if author_roles_json.blank?
    self.approver_roles_json = DEFAULT_APPROVER_ROLES if approver_roles_json.blank?
    self.max_estimated_cost_usd = DEFAULT_MAX_ESTIMATED_COST_USD if max_estimated_cost_usd.blank?
    self.metadata_json = metadata_json.to_h
    self.allowed_internal_actions_json = DEFAULT_ALLOWED_INTERNAL_ACTIONS if allowed_internal_actions_json.blank?
    self.automation_retry_limit = DEFAULT_AUTOMATION_RETRY_LIMIT if automation_retry_limit.blank?
    self.automation_confidence_threshold = DEFAULT_AUTOMATION_CONFIDENCE_THRESHOLD if automation_confidence_threshold.blank?
  end

  def default_allowed_target_systems
    Search::AssistantQueryService::SUPPORTED_DRAFT_TARGETS
  end

  def allowed_roles_for(lifecycle_operation)
    case lifecycle_operation.to_s
    when AgentActions::PolicyEngine::LIFECYCLE_APPROVE,
         AgentActions::PolicyEngine::LIFECYCLE_REJECT,
         AgentActions::PolicyEngine::LIFECYCLE_REQUEST_CHANGES
      approver_roles
    else
      author_roles
    end
  end

  def normalize_collection(values, allowed)
    Array(values).map(&:to_s).select { |value| allowed.include?(value) }.uniq
  end

  def validate_allowed_target_systems
    invalid_values = Array(allowed_target_systems_json).map(&:to_s) - Search::AssistantQueryService::SUPPORTED_DRAFT_TARGETS
    errors.add(:allowed_target_systems_json, "contains unsupported systems") if invalid_values.any?
  end

  def validate_allowed_draft_types
    invalid_values = Array(allowed_draft_types_json).map(&:to_s) - AgentAction::DRAFT_TYPE_OPTIONS
    errors.add(:allowed_draft_types_json, "contains unsupported draft types") if invalid_values.any?
  end

  def validate_allowed_lifecycle_operations
    invalid_values = Array(allowed_lifecycle_operations_json).map(&:to_s) - AgentActions::PolicyEngine::LIFECYCLE_OPTIONS
    errors.add(:allowed_lifecycle_operations_json, "contains unsupported operations") if invalid_values.any?
  end

  def validate_author_roles
    invalid_values = Array(author_roles_json).map(&:to_s) - Membership.roles.keys
    errors.add(:author_roles_json, "contains unsupported roles") if invalid_values.any?
  end

  def validate_approver_roles
    invalid_values = Array(approver_roles_json).map(&:to_s) - Membership.roles.keys
    errors.add(:approver_roles_json, "contains unsupported roles") if invalid_values.any?
  end

  def validate_allowed_internal_actions
    invalid_values = Array(allowed_internal_actions_json).map(&:to_s) - INTERNAL_ACTION_OPTIONS
    errors.add(:allowed_internal_actions_json, "contains unsupported actions") if invalid_values.any?
  end
end
