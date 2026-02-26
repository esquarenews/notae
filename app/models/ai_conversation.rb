class AiConversation < ApplicationRecord
  STATUS_SUCCESS = "success"
  STATUS_NOTICE = "notice"
  STATUSES = [ STATUS_SUCCESS, STATUS_NOTICE ].freeze

  belongs_to :user
  belongs_to :workspace
  belongs_to :page, optional: true

  validates :scope, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :prompt, presence: true
  validates :answer, presence: true

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :recent_first, -> { order(created_at: :desc) }
end
