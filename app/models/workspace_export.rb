require "base64"

class WorkspaceExport < ApplicationRecord
  encrypts :token, deterministic: true

  belongs_to :workspace
  belongs_to :requested_by, class_name: "User"

  has_one_attached :archive_file

  attribute :status, :integer, default: 0
  enum :status, { pending: 0, ready: 1, failed: 2 }, default: :pending, scopes: false

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :token_entropy_is_sufficient

  before_validation :ensure_token, on: :create
  before_validation :set_default_expiry, on: :create

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(arel_table[:expires_at].gt(Time.current)) }

  def expired?
    expires_at <= Time.current
  end

  def active?
    !expired?
  end

  def downloadable?
    ready? && active? && archive_file.attached?
  end

  def mark_ready!
    update!(
      status: :ready,
      completed_at: Time.current,
      failed_at: nil,
      error_message: ""
    )
  end

  def mark_failed!(message)
    update!(
      status: :failed,
      failed_at: Time.current,
      error_message: message.to_s.truncate(500)
    )
  end

  private

  def ensure_token
    self.token ||= loop do
      candidate = SecureRandom.urlsafe_base64(32)
      break candidate unless self.class.exists?(token: candidate)
    end
  end

  def set_default_expiry
    self.expires_at ||= 2.hours.from_now
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
