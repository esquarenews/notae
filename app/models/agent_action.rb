class AgentAction < ApplicationRecord
  PROPOSED_BY_OPTIONS = %w[manual ai_assistant automation_agent api].freeze
  TARGET_SYSTEM_OPTIONS = %w[gmail email github slack calendar crm notae].freeze
  DRAFT_TYPE_OPTIONS = %w[email_draft github_comment_draft task_ticket calendar_hold nota_draft].freeze
  TARGET_SYSTEMS_BY_DRAFT_TYPE = {
    "email_draft" => %w[gmail email],
    "github_comment_draft" => %w[github],
    "task_ticket" => %w[github slack crm],
    "calendar_hold" => %w[calendar],
    "nota_draft" => %w[notae]
  }.freeze
  STATUS_PENDING = "pending".freeze
  STATUS_CHANGES_REQUESTED = "changes_requested".freeze
  STATUS_APPROVED = "approved".freeze
  STATUS_REJECTED = "rejected".freeze
  STATUS_FAILED = "failed".freeze
  STATUS_OPTIONS = [ STATUS_PENDING, STATUS_CHANGES_REQUESTED, STATUS_APPROVED, STATUS_REJECTED, STATUS_FAILED ].freeze

  belongs_to :workspace
  belongs_to :user
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :rejected_by, class_name: "User", optional: true
  has_many :agent_action_events, dependent: :destroy

  validates :proposed_by, inclusion: { in: PROPOSED_BY_OPTIONS }
  validates :target_system, inclusion: { in: TARGET_SYSTEM_OPTIONS }
  validates :draft_type, inclusion: { in: DRAFT_TYPE_OPTIONS }
  validates :status, inclusion: { in: STATUS_OPTIONS }
  validates :title, presence: true
  validates :approval_required, inclusion: { in: [ true, false ] }
  validates :dry_run, inclusion: { in: [ true, false ] }
  validate :validate_target_system_for_draft_type
  validate :validate_payload_for_draft_type

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :pending, -> { where(status: STATUS_PENDING) }
  scope :changes_requested, -> { where(status: STATUS_CHANGES_REQUESTED) }
  scope :recent_first, -> { order(created_at: :desc) }

  def pending?
    status == STATUS_PENDING
  end

  def changes_requested?
    status == STATUS_CHANGES_REQUESTED
  end

  def approved?
    status == STATUS_APPROVED
  end

  def rejected?
    status == STATUS_REJECTED
  end

  def failed?
    status == STATUS_FAILED
  end

  def reversed?
    result_json.to_h["reversal"].present?
  end

  def reversible?
    approved? && !reversed? && result_json.to_h["target_id"].present? && reversible_target_type?
  end

  def editable?
    pending? || changes_requested?
  end

  def approvable?
    pending? && approval_required?
  end

  def request_changes_allowed?
    pending?
  end

  def log_event!(event_type:, actor: nil, comment: nil, details: {})
    AgentActionEvent.record!(agent_action: self, actor: actor, event_type: event_type, comment: comment, details: details)
  end

  def payload
    payload_json.to_h
  end

  def supported_target_systems
    TARGET_SYSTEMS_BY_DRAFT_TYPE.fetch(draft_type.to_s, TARGET_SYSTEM_OPTIONS)
  end

  def review_history
    agent_action_events.order(:sequence_number)
  end

  private

  def reversible_target_type?
    %w[Page DbRow KalendariumEvent].include?(result_json.to_h["target_type"].to_s)
  end

  def validate_target_system_for_draft_type
    return if draft_type.blank? || target_system.blank?
    return if supported_target_systems.include?(target_system.to_s)

    errors.add(:target_system, "is not supported for #{draft_type.humanize.downcase}")
  end

  def validate_payload_for_draft_type
    case draft_type.to_s
    when "email_draft"
      validate_presence_of_payload_value("subject", "must include an email subject")
      validate_presence_of_payload_value("body", "must include email body content")
      recipients = Array(payload["to"]) + Array(payload["cc"])
      errors.add(:payload_json, "must include at least one recipient") if recipients.map(&:to_s).map(&:strip).reject(&:blank?).empty?
    when "github_comment_draft"
      validate_presence_of_payload_value("repository", "must include a repository")
      validate_presence_of_payload_value("target_reference", "must include an issue or pull request reference")
      validate_presence_of_payload_value("body", "must include comment text")
    when "task_ticket"
      validate_presence_of_payload_value("project", "must include a destination project or queue")
      validate_presence_of_payload_value("title", "must include a ticket title")
      validate_presence_of_payload_value("body", "must include ticket details")
    when "calendar_hold"
      validate_presence_of_payload_value("title", "must include an event title")
      starts_at = parse_payload_time("starts_at")
      ends_at = parse_payload_time("ends_at")
      errors.add(:payload_json, "must include a valid start time") if starts_at.nil?
      errors.add(:payload_json, "must include a valid end time") if ends_at.nil?
      if starts_at.present? && ends_at.present? && ends_at <= starts_at
        errors.add(:payload_json, "must end after it starts")
      end
    when "nota_draft"
      validate_presence_of_payload_value("title", "must include a Nota title")
      validate_presence_of_payload_value("body", "must include Nota content")
    end
  end

  def validate_presence_of_payload_value(key, message)
    errors.add(:payload_json, message) if payload[key].to_s.strip.blank?
  end

  def parse_payload_time(key)
    value = payload[key].to_s.strip
    return nil if value.blank?

    Time.zone.parse(value)
  rescue ArgumentError, TypeError
    nil
  end
end
