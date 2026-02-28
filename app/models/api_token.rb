require "base64"

class ApiToken < ApplicationRecord
  encrypts :token, deterministic: true

  belongs_to :user

  validates :name, presence: true
  validates :token, presence: true, uniqueness: true
  validate :token_entropy_is_sufficient

  before_validation :set_default_name
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

  def touch_last_used!
    return unless last_used_at.nil? || last_used_at < 1.minute.ago

    update_column(:last_used_at, Time.current)
  end

  private

  def set_default_name
    self.name = "default" if name.blank?
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
