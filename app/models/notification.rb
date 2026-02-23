class Notification < ApplicationRecord
  TYPES = %w[mention].freeze

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
end
