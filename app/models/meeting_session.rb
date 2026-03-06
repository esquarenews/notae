class MeetingSession < ApplicationRecord
  CAPTURE_MODES = %w[online_bot in_person_mic upload].freeze
  PROVIDERS = %w[google_meet zoom teams local].freeze
  STATUSES = %w[scheduled joining recording uploading processing summarizing proposing completed failed cancelled].freeze
  ACTIVE_STATUSES = %w[scheduled joining recording uploading processing summarizing proposing].freeze

  belongs_to :workspace
  belongs_to :kalendarium_event, optional: true
  belongs_to :page, optional: true
  belongs_to :created_by, class_name: "User"
  belongs_to :updated_by, class_name: "User"

  has_many :meeting_utterances, dependent: :destroy
  has_many :meeting_bot_runs, dependent: :destroy
  has_one :latest_meeting_bot_run, -> { order(created_at: :desc) }, class_name: "MeetingBotRun"
  has_many_attached :capture_files

  validates :title, presence: true, length: { maximum: 200 }
  validates :capture_mode, inclusion: { in: CAPTURE_MODES }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :status, inclusion: { in: STATUSES }

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :active, -> { where(status: ACTIVE_STATUSES) }

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def processing?
    %w[processing summarizing proposing].include?(status)
  end

  def transcript_text_from_utterances
    meeting_utterances.ordered.map do |utterance|
      timestamp = self.class.milliseconds_to_clock(utterance.started_ms.to_i)
      speaker = utterance.speaker_name.to_s.presence || utterance.speaker_key.to_s
      "[#{timestamp}] #{speaker}: #{utterance.text.to_s.strip}"
    end.join("\n")
  end

  def self.milliseconds_to_clock(value)
    seconds = [ value.to_i / 1000, 0 ].max
    minutes = seconds / 60
    remaining_seconds = seconds % 60
    format("%02d:%02d", minutes, remaining_seconds)
  end

  def self.normalize_join_url(raw_url)
    value = raw_url.to_s.strip
    return nil if value.blank?
    return value if value.start_with?("https://", "http://")

    nil
  end
end
