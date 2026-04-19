class Notification < ApplicationRecord
  TYPE_MENTION = "mention".freeze
  TYPE_CALENDAR_REMINDER = "calendar_reminder".freeze
  TYPE_AGENT_ACTION_APPROVAL_REQUESTED = "agent_action_approval_requested".freeze
  TYPE_AGENT_ACTION_CHANGES_REQUESTED = "agent_action_changes_requested".freeze
  TYPE_AGENT_ACTION_RESUBMITTED = "agent_action_resubmitted".freeze
  TYPE_AGENT_ACTION_APPROVED = "agent_action_approved".freeze
  TYPE_AGENT_ACTION_REJECTED = "agent_action_rejected".freeze
  TYPE_WORKFLOW_FAILED = "workflow_failed".freeze
  TYPE_KNOWLEDGE_SUGGESTION_READY = "knowledge_suggestion_ready".freeze
  TYPE_CODEX_REQUEST_COMPLETED = "codex_request_completed".freeze
  TYPE_TEST_PUSH = "test_push".freeze
  TYPES = [
    TYPE_MENTION,
    TYPE_CALENDAR_REMINDER,
    TYPE_AGENT_ACTION_APPROVAL_REQUESTED,
    TYPE_AGENT_ACTION_CHANGES_REQUESTED,
    TYPE_AGENT_ACTION_RESUBMITTED,
    TYPE_AGENT_ACTION_APPROVED,
    TYPE_AGENT_ACTION_REJECTED,
    TYPE_WORKFLOW_FAILED,
    TYPE_KNOWLEDGE_SUGGESTION_READY,
    TYPE_CODEX_REQUEST_COMPLETED,
    TYPE_TEST_PUSH
  ].freeze

  belongs_to :workspace
  belongs_to :recipient, class_name: "User"
  belongs_to :actor, class_name: "User"
  belongs_to :notifiable, polymorphic: true, optional: true
  has_many :web_push_delivery_attempts, dependent: :nullify

  validates :notification_type, presence: true, inclusion: { in: TYPES }

  scope :for_recipient, ->(user) { where(recipient_id: user.id) }
  scope :unread, -> { where(read_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  after_commit :enqueue_web_push_delivery, on: :create

  def mark_as_read!
    update!(read_at: Time.current)
  end

  def agent_action_notification?
    notification_type.to_s.start_with?("agent_action_")
  end

  def knowledge_suggestion_notification?
    notification_type == TYPE_KNOWLEDGE_SUGGESTION_READY
  end

  def codex_completion_notification?
    notification_type == TYPE_CODEX_REQUEST_COMPLETED
  end

  def codex_completion_title
    self.class.normalize_codex_completion_title(metadata["title"])
  end

  def self.normalize_codex_completion_title(raw_title)
    title = raw_title.to_s.strip
    return "codex: request completed" if title.blank?

    if title.match?(/\Acodex:/i)
      suffix = title.sub(/\Acodex:\s*/i, "").strip
      return "codex: request completed" if suffix.blank?

      return "codex: #{suffix}"
    end

    suffix = title.sub(/\Acodex\b[:\-\s]*/i, "").strip
    suffix = "request completed" if suffix.blank?
    "codex: #{suffix}"
  end

  private

  def enqueue_web_push_delivery
    return unless WebPush::Configuration.configured?
    return if notification_type == TYPE_TEST_PUSH
    return unless recipient.web_push_subscriptions.exists?

    WebPush::DeliverNotificationJob.perform_later(id)
  rescue StandardError => error
    raise unless Queueing::JobEnqueueSafety.queue_unavailable?(error)

    Rails.logger.warn("Web push queue unavailable for notification=#{id}: #{error.class}: #{error.message}")
  end
end
