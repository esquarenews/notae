require "base64"

class ApiToken < ApplicationRecord
  SCOPE_ALL = "*".freeze
  SCOPE_WORKSPACES_READ = "workspaces:read".freeze
  SCOPE_PAGES_READ = "pages:read".freeze
  SCOPE_PAGES_WRITE = "pages:write".freeze
  SCOPE_PAGE_DOCUMENTS_READ = "page_documents:read".freeze
  SCOPE_PAGE_DOCUMENTS_WRITE = "page_documents:write".freeze
  SCOPE_DATABASES_READ = "databases:read".freeze
  SCOPE_DATABASES_WRITE = "databases:write".freeze
  SCOPE_CALENDAR_READ = "calendar:read".freeze
  SCOPE_CALENDAR_WRITE = "calendar:write".freeze
  SCOPE_NOTIFICATIONS_WRITE = "notifications:write".freeze
  SCOPE_KNOWLEDGE_READ = "knowledge:read".freeze
  SCOPE_KNOWLEDGE_WRITE = "knowledge:write".freeze
  SCOPE_AGENT_ACTIONS_READ = "agent_actions:read".freeze
  SCOPE_AGENT_ACTIONS_WRITE = "agent_actions:write".freeze
  SCOPE_MEETINGS_READ = "meetings:read".freeze
  SCOPE_MEETINGS_WRITE = "meetings:write".freeze
  SUPPORTED_SCOPES = [
    SCOPE_ALL,
    SCOPE_WORKSPACES_READ,
    SCOPE_PAGES_READ,
    SCOPE_PAGES_WRITE,
    SCOPE_PAGE_DOCUMENTS_READ,
    SCOPE_PAGE_DOCUMENTS_WRITE,
    SCOPE_DATABASES_READ,
    SCOPE_DATABASES_WRITE,
    SCOPE_CALENDAR_READ,
    SCOPE_CALENDAR_WRITE,
    SCOPE_NOTIFICATIONS_WRITE,
    SCOPE_KNOWLEDGE_READ,
    SCOPE_KNOWLEDGE_WRITE,
    SCOPE_AGENT_ACTIONS_READ,
    SCOPE_AGENT_ACTIONS_WRITE,
    SCOPE_MEETINGS_READ,
    SCOPE_MEETINGS_WRITE
  ].freeze

  encrypts :token, deterministic: true

  belongs_to :user
  has_many :api_token_audit_events, dependent: :destroy

  validates :name, presence: true
  validates :token, presence: true, uniqueness: true
  validate :token_entropy_is_sufficient
  validate :scopes_are_supported

  before_validation :set_default_name
  before_validation :normalize_scopes_json
  before_validation :ensure_token, on: :create

  scope :active, lambda {
    where(revoked_at: nil).where(
      arel_table[:expires_at].eq(nil).or(arel_table[:expires_at].gt(Time.current))
    )
  }

  def revoke!
    update!(revoked_at: Time.current)
  end

  def active?
    revoked_at.nil? && (expires_at.nil? || expires_at > Time.current)
  end

  def scopes
    raw_scopes = self[:scopes_json]
    values = raw_scopes.is_a?(Array) ? raw_scopes : []
    normalized = values.map(&:to_s).reject(&:blank?).uniq

    normalized.presence || [ SCOPE_ALL ]
  end

  def allows_scope?(scope)
    scope_name = scope.to_s
    scopes.include?(SCOPE_ALL) || scopes.include?(scope_name)
  end

  def allows_any_scope?(*requested_scopes)
    normalized_scopes = requested_scopes.flatten.map(&:to_s).reject(&:blank?).uniq
    return true if normalized_scopes.empty?

    normalized_scopes.any? { |scope| allows_scope?(scope) }
  end

  def touch_last_used!
    return unless last_used_at.nil? || last_used_at < 1.minute.ago

    update_column(:last_used_at, Time.current)
  end

  private

  def set_default_name
    self.name = "default" if name.blank?
  end

  def normalize_scopes_json
    self.scopes_json = scopes
  end

  def ensure_token
    self.token ||= loop do
      candidate = SecureRandom.urlsafe_base64(32)
      break candidate unless self.class.exists?(token: candidate)
    end
  end

  def token_entropy_is_sufficient
    return if token.blank?

    decoded = Base64.urlsafe_decode64(padded_token(token))
    return if decoded.bytesize >= 32

    errors.add(:token, "must include at least 32 bytes of entropy")
  rescue ArgumentError
    errors.add(:token, "must be URL-safe base64")
  end

  def scopes_are_supported
    unsupported_scopes = scopes - SUPPORTED_SCOPES
    return if unsupported_scopes.empty?

    errors.add(:scopes_json, "contains unsupported scopes")
  end

  def padded_token(value)
    value + ("=" * ((4 - (value.length % 4)) % 4))
  end
end
