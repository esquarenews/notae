class MeetingSession < ApplicationRecord
  CAPTURE_MODES = %w[online_bot in_person_mic upload].freeze
  PROVIDERS = %w[google_meet zoom teams local].freeze
  STATUSES = %w[scheduled joining recording uploading processing summarizing proposing completed failed cancelled].freeze

  belongs_to :workspace
  belongs_to :kalendarium_event, optional: true
  belongs_to :page, optional: true
  belongs_to :created_by, class_name: "User"
  belongs_to :updated_by, class_name: "User"

  has_many :meeting_utterances, dependent: :destroy
  has_many :meeting_bot_runs, dependent: :destroy
  has_many_attached :capture_files

  validates :title, presence: true, length: { maximum: 200 }
  validates :capture_mode, inclusion: { in: CAPTURE_MODES }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[scheduled joining recording uploading processing summarizing proposing]) }

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def processing?
    %w[processing summarizing proposing].include?(status)
  end
end
