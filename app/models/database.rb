class Database < ApplicationRecord
  has_paper_trail
  COVER_PRESET_KEYS = Page::COVER_PRESET_KEYS
  ICON_SUGGESTIONS = Page::ICON_SUGGESTIONS
  FONT_STYLES = Page::FONT_STYLES

  belongs_to :workspace
  belongs_to :linked_page, class_name: "Page", optional: true
  has_many :db_properties, -> { order(:position, :created_at) }, dependent: :destroy
  has_many :db_rows, dependent: :destroy
  has_many :database_views, dependent: :destroy
  has_many :favorites, as: :favoritable, dependent: :destroy
  has_many :search_chunks, dependent: :nullify
  has_one_attached :cover_image

  validates :name, presence: true
  validates :name, uniqueness: { scope: :workspace_id }
  validates :locked, inclusion: { in: [ true, false ] }
  validates :small_text, inclusion: { in: [ true, false ] }
  validates :font_style, inclusion: { in: FONT_STYLES }
  validates :icon, length: { maximum: 8 }, allow_blank: true
  validates :cover_preset_key, inclusion: { in: COVER_PRESET_KEYS }, allow_blank: true
  validates :cover_focal_y,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validate :linked_page_workspace_matches

  scope :active, lambda {
    if column_names.include?("archived_at")
      where(archived_at: nil)
    else
      all
    end
  }
  scope :archived, lambda {
    if column_names.include?("archived_at")
      where.not(archived_at: nil)
    else
      none
    end
  }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  before_validation :normalize_icon

  def cover?
    cover_image.attached? || cover_preset_key.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def restore!
    update!(archived_at: nil)
  end

  def archived?
    archived_at.present?
  end

  private

  def normalize_icon
    normalized = icon.to_s.strip.presence
    self.icon = normalized&.scan(/\X/)&.first(2)&.join
  end

  def linked_page_workspace_matches
    return if linked_page.blank?
    return if linked_page.workspace_id == workspace_id

    errors.add(:linked_page_id, "must belong to the same workspace")
  end
end
