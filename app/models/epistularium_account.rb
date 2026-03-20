require "json"

class EpistulariumAccount < ApplicationRecord
  PROVIDERS = %w[gmail imap amazon_workmail].freeze
  STATUSES = %w[connected sync_error disconnected].freeze
  OWNER_TYPES = %w[User Workspace].freeze
  DEFAULT_SYNC_ACTIVITY_TIMEOUT = 20.minutes

  encrypts :access_token
  encrypts :refresh_token
  encrypts :provider_username
  encrypts :provider_password
  encrypts :oauth_client_id
  encrypts :oauth_client_secret

  belongs_to :workspace
  belongs_to :owner, polymorphic: true
  belongs_to :created_by, class_name: "User"

  has_many :epistularium_messages, dependent: :destroy

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :label, presence: true, length: { maximum: 120 }
  validates :status, inclusion: { in: STATUSES }
  validates :owner_type, inclusion: { in: OWNER_TYPES }
  validate :provider_credentials_present
  validate :imap_host_is_not_an_smtp_endpoint
  validate :amazon_workmail_username_looks_like_email

  before_validation :normalize_account_fields

  scope :active, -> { where(enabled: true) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  def shared_account?
    owner_type == "Workspace"
  end

  def user_account?
    owner_type == "User"
  end

  def google_tokens_configured?
    credential_value_usable?(access_token) || credential_value_usable?(refresh_token)
  end

  def imap_credentials_configured?
    credential_value_usable?(provider_username) &&
      credential_value_usable?(provider_password) &&
      imap_host.present?
  end

  def imap_host
    settings_json.to_h["imap_host"].to_s.strip.presence
  end

  def imap_port
    value = settings_json.to_h["imap_port"]
    return 993 if value.blank?

    value.to_i.positive? ? value.to_i : 993
  end

  def imap_ssl?
    raw = settings_json.to_h["imap_ssl"]
    raw.nil? ? true : ActiveModel::Type::Boolean.new.cast(raw)
  end

  def imap_ssl
    imap_ssl?
  end

  def sent_mailbox_name
    raw = settings_json.to_h["sent_mailbox"].to_s.strip
    return "Sent Items" if provider == "amazon_workmail" && raw.blank?
    return "Sent" if raw.blank?

    raw
  end

  def sent_mailbox
    settings_json.to_h["sent_mailbox"].to_s.strip.presence
  end

  def sync_started_at
    parsed_settings_time("sync_started_at")
  end

  def sync_enqueued_at
    parsed_settings_time("sync_enqueued_at")
  end

  def sync_active?(stale_after: DEFAULT_SYNC_ACTIVITY_TIMEOUT)
    started_at = sync_started_at
    started_at.present? && started_at > stale_after.ago
  end

  def stale_sync?(stale_after: DEFAULT_SYNC_ACTIVITY_TIMEOUT)
    started_at = sync_started_at
    started_at.present? && started_at <= stale_after.ago
  end

  def sync_recently_enqueued?(within:)
    return false unless within.to_i.positive?

    enqueued_at = sync_enqueued_at
    enqueued_at.present? && enqueued_at > within.ago
  end

  def sync_queue_stalled?(stale_after:)
    enqueued_at = sync_enqueued_at
    enqueued_at.present? && enqueued_at <= stale_after.ago && !sync_active?
  end

  def mark_sync_started!(at: Time.current)
    update_sync_setting!("sync_started_at", normalize_sync_timestamp(at))
  end

  def clear_sync_started!
    clear_sync_setting!("sync_started_at")
  end

  def mark_sync_enqueued!(at: Time.current)
    update_sync_setting!("sync_enqueued_at", normalize_sync_timestamp(at))
  end

  def clear_sync_enqueued!
    clear_sync_setting!("sync_enqueued_at")
  end

  def clear_stale_sync_state!(stale_after: DEFAULT_SYNC_ACTIVITY_TIMEOUT)
    return false unless stale_sync?(stale_after: stale_after)

    clear_sync_started!
    true
  end

  private

  def provider_credentials_present
    case provider
    when "gmail"
      return if access_token.present? || refresh_token.present?

      errors.add(:base, "Gmail accounts require an access token or refresh token")
    when "imap", "amazon_workmail"
      errors.add(:provider_username, "is required for IMAP") if provider_username.blank?
      errors.add(:provider_password, "is required for IMAP") if provider_password.blank?
      errors.add(:base, "IMAP host is required") if imap_host.blank?
    end
  end

  def imap_host_is_not_an_smtp_endpoint
    return unless %w[imap amazon_workmail].include?(provider)

    host = imap_host.to_s.downcase
    return if host.blank?
    return unless host.start_with?("smtp.") || host.include?(".smtp.") || host.include?("smtp.mail.")

    errors.add(:base, smtp_endpoint_message)
  end

  def amazon_workmail_username_looks_like_email
    return unless provider == "amazon_workmail"

    username = provider_username.to_s.strip
    return if username.blank?
    return if username.include?("@")

    errors.add(:base, "Amazon WorkMail username must be the full email address for the mailbox, not a short name.")
  end

  def normalize_account_fields
    self.provider_username = provider_username.to_s.strip.presence
    self.provider_password = provider_password.to_s.strip.presence
    self.access_token = access_token.to_s.strip.presence
    self.refresh_token = refresh_token.to_s.strip.presence
    self.oauth_client_id = oauth_client_id.to_s.strip.presence
    self.oauth_client_secret = oauth_client_secret.to_s.strip.presence
    self.remote_account_id = remote_account_id.to_s.strip.presence

    normalized_settings = settings_json.to_h.deep_dup
    normalized_settings["imap_host"] = normalized_settings["imap_host"].to_s.strip.presence
    normalized_settings["imap_port"] = normalized_settings["imap_port"].to_i if normalized_settings["imap_port"].present?
    normalized_settings["imap_ssl"] = ActiveModel::Type::Boolean.new.cast(normalized_settings["imap_ssl"]) unless normalized_settings["imap_ssl"].nil?
    normalized_settings["sent_mailbox"] = normalized_settings["sent_mailbox"].to_s.strip.presence
    self.settings_json = normalized_settings.compact
  end

  def credential_value_usable?(raw_value)
    value = raw_value.to_s.strip
    return false if value.blank?
    return false if serialized_encryption_payload?(value)

    true
  end

  def serialized_encryption_payload?(value)
    parsed = JSON.parse(value)
    return false unless parsed.is_a?(Hash)

    payload = parsed["p"]
    header = parsed["h"]
    payload.present? &&
      header.is_a?(Hash) &&
      header["iv"].present? &&
      header["at"].present?
  rescue JSON::ParserError
    false
  end

  def smtp_endpoint_message
    if provider == "amazon_workmail"
      "Use the Amazon WorkMail IMAP endpoint, not SMTP. Example: imap.mail.<region>.awsapps.com on port 993."
    else
      "IMAP host looks like an SMTP server. Use the incoming IMAP endpoint on port 993."
    end
  end

  def parsed_settings_time(key)
    value = settings_json.to_h[key].to_s.strip
    return nil if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end

  def normalize_sync_timestamp(value)
    timestamp =
      case value
      when String
        Time.iso8601(value)
      else
        value.respond_to?(:iso8601) ? value : nil
      end
    timestamp&.utc&.iso8601
  rescue ArgumentError
    nil
  end

  def update_sync_setting!(key, value)
    updated_settings = settings_json.to_h.deep_dup
    if value.present?
      updated_settings[key] = value
    else
      updated_settings.delete(key)
    end

    update_columns(settings_json: updated_settings, updated_at: Time.current)
    self.settings_json = updated_settings
  end

  def clear_sync_setting!(key)
    update_sync_setting!(key, nil)
  end
end
