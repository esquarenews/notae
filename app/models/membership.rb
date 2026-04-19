class Membership < ApplicationRecord
  has_paper_trail

  belongs_to :workspace
  belongs_to :user

  enum :role, {
    member: 0,
    admin: 1,
    owner: 2,
    guest: 3,
    auditor: 4,
    automation_agent: 5
  }, default: :member

  validates :user_id, uniqueness: { scope: :workspace_id }

  def admin_or_owner?
    admin? || owner?
  end

  def read_only?
    guest? || auditor?
  end

  def content_editor?
    member? || admin? || owner?
  end

  def can_author_agent_actions?
    content_editor? || automation_agent?
  end

  def audit_reviewer?
    admin_or_owner? || auditor?
  end

  def notification_preferences
    raw_preferences = notification_preferences_json
    raw_preferences.is_a?(Hash) ? raw_preferences : {}
  end

  def workspace_email_notify_activity_override
    raw_value = notification_preferences["email_notify_activity"]
    return nil if raw_value.nil?

    ActiveModel::Type::Boolean.new.cast(raw_value)
  end

  def workspace_email_notify_activity_enabled?(default:)
    override = workspace_email_notify_activity_override
    override.nil? ? default : override
  end

  def workspace_push_notification_preferences
    raw_preferences = notification_preferences["push_notification_preferences"]
    raw_preferences.is_a?(Hash) ? raw_preferences : {}
  end

  def workspace_push_notification_override(notification_type)
    raw_value = workspace_push_notification_preferences[notification_type.to_s]
    return nil if raw_value.nil?

    ActiveModel::Type::Boolean.new.cast(raw_value)
  end

  def workspace_push_notification_enabled?(notification_type, default:)
    override = workspace_push_notification_override(notification_type)
    override.nil? ? default : override
  end
end
