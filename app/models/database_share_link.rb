require "base64"

class DatabaseShareLink < ApplicationRecord
  encrypts :token, deterministic: true

  belongs_to :workspace
  belongs_to :database
  belongs_to :created_by, class_name: "User"

  validates :token, presence: true, uniqueness: true
  validate :token_entropy_is_sufficient

  before_validation :set_workspace_from_database
  before_validation :ensure_token, on: :create

  scope :for_database, ->(database) { where(database_id: database.id) }
  scope :active, lambda {
    where(revoked_at: nil).where(
      arel_table[:expires_at].eq(nil).or(arel_table[:expires_at].gt(Time.current))
    )
  }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :for_public_access, -> { active.joins(:database).merge(Database.active) }

  def revoke!
    update!(revoked_at: Time.current)
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def active?
    !revoked? && !expired?
  end

  private

  def set_workspace_from_database
    self.workspace = database.workspace if database.present?
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

  def padded_token(value)
    value + ("=" * ((4 - (value.length % 4)) % 4))
  end
end
