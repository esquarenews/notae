class DbProperty < ApplicationRecord
  POSITION_GAP = 1024
  TEXT_COLORS = DbRow::ROW_TEXT_COLORS.freeze
  BACKGROUND_COLORS = DbRow::BACKGROUND_COLORS.freeze

  has_paper_trail

  attribute :property_type, :integer, default: 0
  enum :property_type, { text: 0, number: 1, date: 2, checkbox: 3, select: 4 }, default: :text, scopes: false

  belongs_to :workspace
  belongs_to :database, touch: true

  has_many :db_cells, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :database_id, case_sensitive: false }
  validates :position, numericality: { greater_than: 0, only_integer: true }
  validates :text_color, inclusion: { in: TEXT_COLORS }
  validates :background_color, inclusion: { in: BACKGROUND_COLORS }, if: -> { self.class.column_names.include?("background_color") }

  scope :ordered, -> { order(:position, :created_at) }
  scope :for_database, ->(database) { where(database_id: database.id) }
  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }

  before_validation :set_workspace_from_database
  before_validation :set_initial_position, on: :create
  before_validation :normalize_text_color!
  before_validation :normalize_background_color!, if: -> { self.class.column_names.include?("background_color") }

  def column_bold?
    text_bold?
  end

  def column_italic?
    text_italic?
  end

  def column_text_color
    TEXT_COLORS.include?(text_color.to_s) ? text_color.to_s : "default"
  end

  def column_background_color
    return "default" unless self.class.column_names.include?("background_color")

    color = self[:background_color].presence || "default"
    BACKGROUND_COLORS.include?(color) ? color : "default"
  end

  def apply_column_style_action!(action:, text_color: nil, background_color: nil)
    case action.to_s
    when "toggle_bold"
      self.text_bold = !column_bold?
    when "toggle_italic"
      self.text_italic = !column_italic?
    when "set_color"
      self.text_color = normalize_text_color(text_color)
    when "set_background_color"
      self.background_color = normalize_background_color(background_color) if self.class.column_names.include?("background_color")
    when "clear_styles"
      self.text_bold = false
      self.text_italic = false
      self.text_color = "default"
      self.background_color = "default" if self.class.column_names.include?("background_color")
    else
      nil
    end
  end

  private

  def set_workspace_from_database
    self.workspace = database.workspace if database.present?
  end

  def set_initial_position
    return if database.blank?
    return if position.present? && position != POSITION_GAP

    sibling_max = self.class.for_database(database).maximum(:position) || 0
    self.position = sibling_max + POSITION_GAP
  end

  def normalize_text_color!(value = text_color)
    self.text_color = normalize_text_color(value)
  end

  def normalize_text_color(value)
    color = value.to_s
    TEXT_COLORS.include?(color) ? color : "default"
  end

  def normalize_background_color!(value = self[:background_color])
    self[:background_color] = normalize_background_color(value)
  end

  def normalize_background_color(value)
    color = value.to_s
    BACKGROUND_COLORS.include?(color) ? color : "default"
  end
end
