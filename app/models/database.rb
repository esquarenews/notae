class Database < ApplicationRecord
  include IconTokenSupport

  has_paper_trail
  COVER_PRESET_KEYS = Page::COVER_PRESET_KEYS
  ICON_SUGGESTIONS = Page::ICON_SUGGESTIONS
  FONT_STYLES = Page::FONT_STYLES

  attribute :permission_mode, :integer, default: 0
  enum :permission_mode, { shared_to_workspace: 0, private_database: 1, specific_users: 2 }, default: :shared_to_workspace

  belongs_to :workspace
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :database_template, optional: true
  belongs_to :linked_page, class_name: "Page", optional: true, inverse_of: :linked_database
  has_many :db_properties, -> { order(:position, :created_at) }, dependent: :destroy
  has_many :db_rows, dependent: :destroy
  has_many :database_views, dependent: :destroy
  has_many :database_templates, dependent: :nullify
  has_many :favorites, as: :favoritable, dependent: :destroy
  has_many :comments, as: :commentable, dependent: :destroy
  has_many :database_shares, dependent: :destroy
  has_many :database_share_links, dependent: :destroy
  has_many :shared_users, through: :database_shares, source: :user
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
  validates :name_column_text_color, inclusion: { in: DbRow::ROW_TEXT_COLORS }, if: -> { self.class.has_column?(:name_column_text_color) }
  validates :name_column_background_color, inclusion: { in: DbRow::BACKGROUND_COLORS }, if: -> { self.class.has_column?(:name_column_background_color) }
  validate :icon_must_be_short_or_custom, if: -> { self.class.has_column?(:icon) }
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
  before_validation :normalize_name_column_text_color!, if: -> { self.class.has_column?(:name_column_text_color) }
  before_validation :normalize_name_column_background_color!, if: -> { self.class.has_column?(:name_column_background_color) }

  def cover?
    cover_image.attached? || cover_preset_key.present? || cover_remote_url.present?
  end

  def cover_remote?
    return false unless self.class.has_column?(:cover_remote_url)

    cover_remote_url.present?
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

  def tab_child?
    linked_page&.tab_child? == true
  end

  def tab_reference_title
    return name unless tab_child?

    linked_page&.tab_reference_title.presence || name
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

  def cover_remote_url
    return nil unless self.class.has_column?(:cover_remote_url)

    self[:cover_remote_url]
  end

  def cover_remote_url=(value)
    return unless self.class.has_column?(:cover_remote_url)

    self[:cover_remote_url] = value
  end

  def cover_remote_thumb_url
    return nil unless self.class.has_column?(:cover_remote_thumb_url)

    self[:cover_remote_thumb_url]
  end

  def cover_remote_thumb_url=(value)
    return unless self.class.has_column?(:cover_remote_thumb_url)

    self[:cover_remote_thumb_url] = value
  end

  def cover_artist_name
    return nil unless self.class.has_column?(:cover_artist_name)

    self[:cover_artist_name]
  end

  def cover_artist_name=(value)
    return unless self.class.has_column?(:cover_artist_name)

    self[:cover_artist_name] = value
  end

  def cover_artist_url
    return nil unless self.class.has_column?(:cover_artist_url)

    self[:cover_artist_url]
  end

  def cover_artist_url=(value)
    return unless self.class.has_column?(:cover_artist_url)

    self[:cover_artist_url] = value
  end

  def cover_source_name
    return nil unless self.class.has_column?(:cover_source_name)

    self[:cover_source_name]
  end

  def cover_source_name=(value)
    return unless self.class.has_column?(:cover_source_name)

    self[:cover_source_name] = value
  end

  def cover_source_url
    return nil unless self.class.has_column?(:cover_source_url)

    self[:cover_source_url]
  end

  def cover_source_url=(value)
    return unless self.class.has_column?(:cover_source_url)

    self[:cover_source_url] = value
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

  def name_column_text_bold
    return false unless self.class.has_column?(:name_column_text_bold)

    self[:name_column_text_bold]
  end

  def name_column_text_bold=(value)
    return unless self.class.has_column?(:name_column_text_bold)

    self[:name_column_text_bold] = ActiveModel::Type::Boolean.new.cast(value)
  end

  def name_column_text_bold?
    ActiveModel::Type::Boolean.new.cast(name_column_text_bold)
  end

  def name_column_text_italic
    return false unless self.class.has_column?(:name_column_text_italic)

    self[:name_column_text_italic]
  end

  def name_column_text_italic=(value)
    return unless self.class.has_column?(:name_column_text_italic)

    self[:name_column_text_italic] = ActiveModel::Type::Boolean.new.cast(value)
  end

  def name_column_text_italic?
    ActiveModel::Type::Boolean.new.cast(name_column_text_italic)
  end

  def name_column_text_color
    return "default" unless self.class.has_column?(:name_column_text_color)

    color = self[:name_column_text_color].presence || "default"
    DbRow::ROW_TEXT_COLORS.include?(color) ? color : "default"
  end

  def name_column_text_color=(value)
    return unless self.class.has_column?(:name_column_text_color)

    self[:name_column_text_color] = normalize_name_column_text_color(value)
  end

  def name_column_background_color
    return "default" unless self.class.has_column?(:name_column_background_color)

    color = self[:name_column_background_color].presence || "default"
    DbRow::BACKGROUND_COLORS.include?(color) ? color : "default"
  end

  def name_column_background_color=(value)
    return unless self.class.has_column?(:name_column_background_color)

    self[:name_column_background_color] = normalize_name_column_background_color(value)
  end

  def apply_name_column_style_action!(action:, text_color: nil, background_color: nil)
    case action.to_s
    when "toggle_bold"
      self.name_column_text_bold = !name_column_text_bold?
    when "toggle_italic"
      self.name_column_text_italic = !name_column_text_italic?
    when "set_color"
      self.name_column_text_color = text_color
    when "set_background_color"
      self.name_column_background_color = background_color
    when "clear_styles"
      self.name_column_text_bold = false
      self.name_column_text_italic = false
      self.name_column_text_color = "default"
      self.name_column_background_color = "default"
    end
  end

  def visible_to_specific_user?(user)
    return false unless user
    return true if created_by_id == user.id

    database_shares.exists?(user_id: user.id)
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

    self.icon = normalize_icon_token(icon)
  end

  def normalize_name_column_text_color!(value = self[:name_column_text_color])
    self[:name_column_text_color] = normalize_name_column_text_color(value)
  end

  def normalize_name_column_text_color(value)
    color = value.to_s
    DbRow::ROW_TEXT_COLORS.include?(color) ? color : "default"
  end

  def normalize_name_column_background_color!(value = self[:name_column_background_color])
    self[:name_column_background_color] = normalize_name_column_background_color(value)
  end

  def normalize_name_column_background_color(value)
    color = value.to_s
    DbRow::BACKGROUND_COLORS.include?(color) ? color : "default"
  end

  def linked_page_workspace_matches
    return unless self.class.has_column?(:linked_page_id)
    return if linked_page.blank?
    return if linked_page.workspace_id == workspace_id

    errors.add(:linked_page_id, "must belong to the same workspace")
  end

  def icon_must_be_short_or_custom
    return if icon.blank?
    return if self.class.custom_emoji_token?(icon)
    return if icon.to_s.scan(/\X/).size <= 2

    errors.add(:icon, "must be a short emoji value")
  end
end
