class Notification < ApplicationRecord
  TYPE_MENTION = "mention".freeze
  TYPE_CALENDAR_REMINDER = "calendar_reminder".freeze
  TYPE_AGENT_ACTION_APPROVAL_REQUESTED = "agent_action_approval_requested".freeze
  TYPE_AGENT_ACTION_CHANGES_REQUESTED = "agent_action_changes_requested".freeze
  TYPE_AGENT_ACTION_RESUBMITTED = "agent_action_resubmitted".freeze
  TYPE_AGENT_ACTION_APPROVED = "agent_action_approved".freeze
  TYPE_AGENT_ACTION_REJECTED = "agent_action_rejected".freeze
  TYPE_WORKFLOW_FAILED = "workflow_failed".freeze
  TYPES = [
    TYPE_MENTION,
    TYPE_CALENDAR_REMINDER,
    TYPE_AGENT_ACTION_APPROVAL_REQUESTED,
    TYPE_AGENT_ACTION_CHANGES_REQUESTED,
    TYPE_AGENT_ACTION_RESUBMITTED,
    TYPE_AGENT_ACTION_APPROVED,
    TYPE_AGENT_ACTION_REJECTED,
    TYPE_WORKFLOW_FAILED
  ].freeze

  belongs_to :workspace
  belongs_to :recipient, class_name: "User"
  belongs_to :actor, class_name: "User"
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :notification_type, presence: true, inclusion: { in: TYPES }

  scope :for_recipient, ->(user) { where(recipient_id: user.id) }
  scope :unread, -> { where(read_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  def mark_as_read!
    update!(read_at: Time.current)
  end

  def agent_action_notification?
    notification_type.to_s.start_with?("agent_action_")
  end
end
