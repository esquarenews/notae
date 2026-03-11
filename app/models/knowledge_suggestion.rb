class KnowledgeSuggestion < ApplicationRecord
  KIND_DAILY_SUMMARY = "daily_summary"
  KIND_PROACTIVE = "proactive"
  KINDS = [ KIND_DAILY_SUMMARY, KIND_PROACTIVE ].freeze

  STATUS_ACTIVE = "active"
  STATUS_DISMISSED = "dismissed"
  STATUS_CONVERTED = "converted"
  STATUSES = [ STATUS_ACTIVE, STATUS_DISMISSED, STATUS_CONVERTED ].freeze

  belongs_to :workspace
  belongs_to :user
  belongs_to :ai_conversation, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :title, presence: true
  validates :summary, presence: true
  validates :generated_at, presence: true

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :recent_first, -> { order(generated_at: :desc, created_at: :desc) }
  scope :active, -> { where(status: STATUS_ACTIVE).where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :daily_summaries, -> { where(kind: KIND_DAILY_SUMMARY) }
  scope :proactive, -> { where(kind: KIND_PROACTIVE) }

  def dismiss!
    update!(status: STATUS_DISMISSED, dismissed_at: Time.current)
  end

  def mark_converted!(target_type:, target_id:)
    metadata = metadata_json.to_h.merge("conversion_target_type" => target_type, "conversion_target_id" => target_id.to_s)
    update!(status: STATUS_CONVERTED, converted_at: Time.current, metadata_json: metadata)
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end
