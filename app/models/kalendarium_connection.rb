require "uri"

class KalendariumConnection < ApplicationRecord
  PROVIDERS = %w[google icloud_caldav ics].freeze
  STATUSES = %w[connected sync_error disconnected].freeze

  encrypts :access_token
  encrypts :refresh_token
  encrypts :provider_username
  encrypts :provider_password
  encrypts :ics_url

  belongs_to :workspace
  belongs_to :owner, polymorphic: true
  belongs_to :created_by, class_name: "User"

  has_many :kalendarium_calendars, dependent: :destroy

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :label, presence: true, length: { maximum: 120 }
  validates :status, inclusion: { in: STATUSES }
  validates :owner_type, inclusion: { in: %w[User Workspace] }
  validate :provider_credentials_present
  validate :ics_url_format_for_feed_provider
  before_validation :normalize_connection_fields

  scope :active, -> { where(enabled: true) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  def shared_connection?
    owner_type == "Workspace"
  end

  def user_connection?
    owner_type == "User"
  end

  private

  def provider_credentials_present
    case provider
    when "google"
      return if access_token.present? || refresh_token.present?

      errors.add(:base, "Google connections require an access token or refresh token")
    when "icloud_caldav"
      errors.add(:provider_username, "is required for iCloud CalDAV") if provider_username.blank?
      errors.add(:provider_password, "is required for iCloud CalDAV") if provider_password.blank?
      if provider_password.present? && provider_password.delete("-").length < 16
        errors.add(:provider_password, "looks too short for an Apple app-specific password")
      end
    when "ics"
      errors.add(:ics_url, "is required for ICS feeds") if ics_url.blank?
    end
  end

  def ics_url_format_for_feed_provider
    return unless provider == "ics"
    return if ics_url.blank?

    uri = URI.parse(ics_url)
    return if uri.is_a?(URI::HTTP) && uri.host.present?

    errors.add(:ics_url, "must be a valid HTTP(S) URL")
  rescue URI::InvalidURIError
    errors.add(:ics_url, "must be a valid HTTP(S) URL")
  end

  def normalize_connection_fields
    self.provider_username = provider_username.to_s.strip.presence
    self.provider_password = normalized_provider_password
    self.ics_url = ics_url.to_s.strip.presence
    self.access_token = access_token.to_s.strip.presence
    self.refresh_token = refresh_token.to_s.strip.presence
    self.remote_account_id = remote_account_id.to_s.strip.presence
  end

  def normalized_provider_password
    value = provider_password.to_s
    return nil if value.blank?

    stripped = value.strip
    stripped = stripped.gsub(/\s+/, "") if provider == "icloud_caldav"
    stripped.presence
  end
end
