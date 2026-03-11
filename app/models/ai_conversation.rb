class AiConversation < ApplicationRecord
  STATUS_SUCCESS = "success"
  STATUS_NOTICE = "notice"
  STATUS_SUGGESTION = "suggestion"
  STATUSES = [ STATUS_SUCCESS, STATUS_NOTICE, STATUS_SUGGESTION ].freeze

  belongs_to :user
  belongs_to :workspace
  belongs_to :page, optional: true

  validates :scope, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :prompt, presence: true
  validates :answer, presence: true

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :recent_first, -> { order(created_at: :desc) }

  def live_web?
    Array(sources).any? do |source|
      normalized = source.respond_to?(:with_indifferent_access) ? source.with_indifferent_access : source
      normalized[:kind].to_s == "Web source"
    end
  end
end
