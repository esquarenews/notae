class Database < ApplicationRecord
  has_paper_trail
  COVER_PRESET_KEYS = Page::COVER_PRESET_KEYS
  ICON_SUGGESTIONS = Page::ICON_SUGGESTIONS

  belongs_to :workspace
  has_many :db_properties, -> { order(:position, :created_at) }, dependent: :destroy
  has_many :db_rows, dependent: :destroy
  has_many :database_views, dependent: :destroy
  has_many :favorites, as: :favoritable, dependent: :destroy
  has_many :search_chunks, dependent: :nullify
  has_one_attached :cover_image

  validates :name, presence: true
  validates :name, uniqueness: { scope: :workspace_id }
  validates :icon, length: { maximum: 8 }, allow_blank: true
  validates :cover_preset_key, inclusion: { in: COVER_PRESET_KEYS }, allow_blank: true
  validates :cover_focal_y,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  before_validation :normalize_icon

  def cover?
    cover_image.attached? || cover_preset_key.present?
  end

  private

  def normalize_icon
    normalized = icon.to_s.strip.presence
    self.icon = normalized&.scan(/\X/)&.first(2)&.join
  end
end
