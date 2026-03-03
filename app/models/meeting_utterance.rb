class MeetingUtterance < ApplicationRecord
  belongs_to :meeting_session

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :speaker_key, presence: true, length: { maximum: 24 }
  validates :text, presence: true

  scope :ordered, -> { order(:position) }
end
