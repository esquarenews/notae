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

  class << self
    def has_column?(name)
      column_names.include?(name.to_s)
    end
  end

  validates :name, presence: true
  validates :name, uniqueness: { scope: :workspace_id }
  validates :locked, inclusion: { in: [ true, false ] }, if: -> { self.class.has_column?(:locked) }
  validates :small_text, inclusion: { in: [ true, false ] }, if: -> { self.class.has_column?(:small_text) }
  validates :font_style, inclusion: { in: FONT_STYLES }, if: -> { self.class.has_column?(:font_style) }
  validates :icon, length: { maximum: 8 }, allow_blank: true, if: -> { self.class.has_column?(:icon) }
  validates :cover_preset_key, inclusion: { in: COVER_PRESET_KEYS }, allow_blank: true, if: -> { self.class.has_column?(:cover_preset_key) }
  validates :cover_focal_y,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 },
            if: -> { self.class.has_column?(:cover_focal_y) }
  validate :linked_page_workspace_matches, if: -> { self.class.has_column?(:linked_page_id) }

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
    return true unless self.class.has_column?(:archived_at)

    update!(archived_at: Time.current)
  end

  def restore!
    return true unless self.class.has_column?(:archived_at)

    update!(archived_at: nil)
  end

  def archived?
    return false unless self.class.has_column?(:archived_at)

    archived_at.present?
  end

  def linked_page_id
    return nil unless self.class.has_column?(:linked_page_id)

    self[:linked_page_id]
  end

  def linked_page_id=(value)
    return unless self.class.has_column?(:linked_page_id)

    self[:linked_page_id] = value
  end

  def description
    return nil unless self.class.has_column?(:description)

    self[:description]
  end

  def description=(value)
    return unless self.class.has_column?(:description)

    self[:description] = value
  end

  def icon
    return nil unless self.class.has_column?(:icon)

    self[:icon]
  end

  def icon=(value)
    return unless self.class.has_column?(:icon)

    self[:icon] = value
  end

  def cover_preset_key
    return nil unless self.class.has_column?(:cover_preset_key)

    self[:cover_preset_key]
  end

  def cover_preset_key=(value)
    return unless self.class.has_column?(:cover_preset_key)

    self[:cover_preset_key] = value
  end

  def cover_focal_y
    return 50 unless self.class.has_column?(:cover_focal_y)

    self[:cover_focal_y]
  end

  def cover_focal_y=(value)
    return unless self.class.has_column?(:cover_focal_y)

    self[:cover_focal_y] = value
  end

  def locked
    return false unless self.class.has_column?(:locked)

    self[:locked]
  end

  def locked=(value)
    return unless self.class.has_column?(:locked)

    self[:locked] = ActiveModel::Type::Boolean.new.cast(value)
  end

  def locked?
    ActiveModel::Type::Boolean.new.cast(locked)
  end

  def small_text
    return false unless self.class.has_column?(:small_text)

    self[:small_text]
  end

  def small_text=(value)
    return unless self.class.has_column?(:small_text)

    self[:small_text] = ActiveModel::Type::Boolean.new.cast(value)
  end

  def small_text?
    ActiveModel::Type::Boolean.new.cast(small_text)
  end

  def font_style
    return "default" unless self.class.has_column?(:font_style)

    self[:font_style].presence || "default"
  end

  def font_style=(value)
    return unless self.class.has_column?(:font_style)

    self[:font_style] = value.presence || "default"
  end

  private

  def normalize_icon
    return unless self.class.has_column?(:icon)

    normalized = icon.to_s.strip.presence
    self.icon = normalized&.scan(/\X/)&.first(2)&.join
  end

  def linked_page_workspace_matches
    return unless self.class.has_column?(:linked_page_id)
    return if linked_page.blank?
    return if linked_page.workspace_id == workspace_id

    errors.add(:linked_page_id, "must belong to the same workspace")
  end
end
