class Invitation < ApplicationRecord
  encrypts :token, deterministic: true

  has_paper_trail

  belongs_to :workspace
  belongs_to :invited_by, class_name: "User"
  belongs_to :accepted_by, class_name: "User", optional: true

  enum :role, { member: 0, admin: 1, owner: 2, guest: 3 }, default: :guest

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validates :email, uniqueness: { scope: :workspace_id, conditions: -> { where(accepted_at: nil) } }

  before_validation :normalize_email
  before_validation :set_token, on: :create
  before_validation :set_expiration, on: :create

  scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

  def expired?
    expires_at <= Time.current
  end

  def accepted?
    accepted_at.present?
  end

  def pending?
    !accepted? && !expired?
  end

  def accept!(user)
    unless pending?
      errors.add(:base, "Invitation is no longer valid")
      raise ActiveRecord::RecordInvalid, self
    end

    transaction do
      membership = Membership.find_or_initialize_by(workspace: workspace, user: user)
      membership.role = role
      membership.save!
      update!(accepted_at: Time.current, accepted_by: user)
    end
  end

  private

  def normalize_email
    self.email = email.to_s.downcase.strip
  end

  def set_token
    self.token ||= SecureRandom.urlsafe_base64(24)
  end

  def set_expiration
    self.expires_at ||= 7.days.from_now
  end
end
