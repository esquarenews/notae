require "digest"
require "json"

class AgentActionEvent < ApplicationRecord
  EVENT_TYPE_OPTIONS = %w[
    policy_evaluated
    draft_created
    draft_updated
    changes_requested
    resubmitted
    approved
    reversed
    rejected
    tool_used
    failed
  ].freeze

  belongs_to :agent_action
  belongs_to :workspace
  belongs_to :actor, class_name: "User", optional: true

  validates :event_type, inclusion: { in: EVENT_TYPE_OPTIONS }
  validates :sequence_number, numericality: { only_integer: true, greater_than: 0 }
  validates :entry_hash, presence: true
  validates :occurred_at, presence: true

  before_validation :assign_workspace!
  before_validation :assign_sequence_number!
  before_validation :assign_occurred_at!
  before_validation :assign_hashes!

  scope :recent_first, -> { order(created_at: :desc) }

  def self.record!(agent_action:, actor:, event_type:, comment: nil, details: {})
    event = create!(
      agent_action: agent_action,
      workspace: agent_action.workspace,
      actor: actor,
      event_type: event_type,
      comment: comment,
      details_json: details
    )
    AuditEventLogger.log_agent_action_event!(event)
    event
  end

  def hash_verification_succeeds?
    computed_entry_hash == entry_hash && previous_chain_hash_verification_succeeds?
  end

  private

  def assign_workspace!
    self.workspace ||= agent_action&.workspace
  end

  def assign_sequence_number!
    return if sequence_number.present? || agent_action.blank?

    last_sequence = self.class.where(agent_action_id: agent_action.id).where.not(id: id).maximum(:sequence_number).to_i
    self.sequence_number = last_sequence + 1
  end

  def assign_occurred_at!
    self.occurred_at ||= Time.current
  end

  def assign_hashes!
    return if agent_action.blank? || sequence_number.blank? || occurred_at.blank?

    self.previous_entry_hash = previous_event&.entry_hash
    self.entry_hash = computed_entry_hash
  end

  def previous_event
    return nil if sequence_number.to_i <= 1

    self.class.where(agent_action_id: agent_action_id || agent_action&.id).where.not(id: id).find_by(sequence_number: sequence_number.to_i - 1)
  end

  def computed_entry_hash
    Digest::SHA256.hexdigest(
      [
        agent_action_id,
        workspace_id,
        actor_id,
        event_type,
        sequence_number,
        comment.to_s,
        canonical_json(details_json),
        previous_entry_hash.to_s,
        occurred_at&.utc&.iso8601
      ].join("|")
    )
  end

  def canonical_json(value)
    JSON.generate(canonicalize(value))
  end

  def canonicalize(value)
    case value
    when Hash
      value.to_h.stringify_keys.sort.to_h { |key, nested| [ key, canonicalize(nested) ] }
    when Array
      value.map { |nested| canonicalize(nested) }
    else
      value
    end
  end

  def previous_chain_hash_verification_succeeds?
    return previous_entry_hash.blank? if previous_event.blank?

    previous_event.entry_hash == previous_entry_hash && previous_event.hash_verification_succeeds?
  end
end
