class MeetingSpeakerAlias < ApplicationRecord
  SOURCES = %w[invitee_match manual].freeze

  belongs_to :workspace

  validates :speaker_fingerprint, presence: true, length: { maximum: 255 }
  validates :display_name, presence: true, length: { maximum: 120 }
  validates :source, inclusion: { in: SOURCES }

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
end
