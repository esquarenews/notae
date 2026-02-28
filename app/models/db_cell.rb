class DbCell < ApplicationRecord
  TRUTHY_VALUES = %w[1 true t yes y on checked].freeze
  FALSY_VALUES = %w[0 false f no n off unchecked].freeze

  has_paper_trail

  belongs_to :workspace
  belongs_to :db_row, touch: true
  belongs_to :db_property

  validates :db_property_id, uniqueness: { scope: :db_row_id }
  validate :relations_share_workspace
  validate :property_belongs_to_row_database

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :for_database, ->(database) { joins(:db_row).where(db_rows: { database_id: database.id }) }

  before_validation :set_workspace_from_row
  before_validation :normalize_value_text_for_property
  after_commit :sync_row_data_cache
  validate :value_matches_property_type

  private

  def set_workspace_from_row
    self.workspace = db_row.workspace if db_row.present?
  end

  def relations_share_workspace
    return if workspace_id.blank?

    if db_row.present? && db_row.workspace_id != workspace_id
      errors.add(:db_row_id, "must belong to the same workspace")
    end

    if db_property.present? && db_property.workspace_id != workspace_id
      errors.add(:db_property_id, "must belong to the same workspace")
    end
  end

  def property_belongs_to_row_database
    return if db_row.blank? || db_property.blank?
    return if db_row.database_id == db_property.database_id

    errors.add(:db_property_id, "must belong to the same database as the row")
  end

  def normalize_value_text_for_property
    return if db_property.blank?

    raw_value = value_text.to_s.strip
    case db_property.property_type
    when "checkbox"
      self.value_text = normalize_checkbox_value(raw_value)
    when "date"
      self.value_text = normalize_date_value(raw_value)
    else
      self.value_text = raw_value
    end
  end

  def value_matches_property_type
    return if db_property.blank?

    case db_property.property_type
    when "number"
      return if value_text.blank?

      Float(value_text)
    when "date"
      return if value_text.blank?

      Date.iso8601(value_text)
    when "checkbox"
      return if %w[true false].include?(value_text)

      errors.add(:value_text, "must be true or false")
    end
  rescue ArgumentError
    expected = db_property.property_type == "number" ? "number" : "date"
    errors.add(:value_text, "must be a valid #{expected}")
  end

  def normalize_checkbox_value(raw_value)
    return "true" if TRUTHY_VALUES.include?(raw_value.downcase)
    return "false" if FALSY_VALUES.include?(raw_value.downcase)

    "false"
  end

  def normalize_date_value(raw_value)
    return "" if raw_value.blank?

    Date.parse(raw_value).iso8601
  rescue ArgumentError
    raw_value
  end

  def sync_row_data_cache
    row = DbRow.find_by(id: db_row_id)
    row&.sync_data_from_cells!
  end
end
