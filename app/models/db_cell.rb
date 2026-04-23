class DbCell < ApplicationRecord
  TRUTHY_VALUES = %w[1 true t yes y on checked].freeze
  FALSY_VALUES = %w[0 false f no n off unchecked].freeze
  PROGRESS_MIN = 0
  PROGRESS_MAX = 10

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
  before_destroy :cache_property_name_for_row_cache
  after_commit :sync_row_data_cache_after_upsert, on: %i[create update]
  after_destroy_commit :sync_row_data_cache_after_destroy
  validate :value_matches_property_type

  class << self
    def progress_value(raw_value, default: PROGRESS_MIN)
      value = raw_value.to_s.strip
      return default if value.blank?

      normalized = Integer(value, exception: false)
      return default if normalized.nil?

      normalized.clamp(PROGRESS_MIN, PROGRESS_MAX)
    end

    def normalize_progress_value(raw_value)
      value = raw_value.to_s.strip
      return PROGRESS_MIN.to_s if value.blank?

      normalized = Integer(value, exception: false)
      return value if normalized.nil?

      normalized.clamp(PROGRESS_MIN, PROGRESS_MAX).to_s
    end
  end

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
    when "progress"
      self.value_text = self.class.normalize_progress_value(raw_value)
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
    when "progress"
      progress_value = Integer(value_text, exception: false)
      return if progress_value.present? && progress_value.between?(PROGRESS_MIN, PROGRESS_MAX)

      errors.add(:value_text, "must be a whole number between #{PROGRESS_MIN} and #{PROGRESS_MAX}")
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

  def sync_row_data_cache_after_upsert
    row = row_for_cache_sync
    key = property_name_for_row_cache
    return if row.blank? || key.blank?

    row.refresh_cached_data_json!(row.data_json.to_h.merge(key => value_text.to_s), enqueue_reindex: false)
  end

  def sync_row_data_cache_after_destroy
    row = row_for_cache_sync
    key = @cached_property_name_for_row_cache.to_s.strip.presence
    return if row.blank? || key.blank?

    row.refresh_cached_data_json!(row.data_json.to_h.except(key), enqueue_reindex: false)
  end

  def row_for_cache_sync
    return db_row if association(:db_row).loaded?

    DbRow.find_by(id: db_row_id)
  end

  def property_name_for_row_cache
    return @cached_property_name_for_row_cache if defined?(@cached_property_name_for_row_cache) && @cached_property_name_for_row_cache.present?

    name =
      if association(:db_property).loaded?
        db_property&.name
      else
        DbProperty.where(id: db_property_id).pick(:name)
      end

    name.to_s.strip.presence
  end

  def cache_property_name_for_row_cache
    @cached_property_name_for_row_cache = property_name_for_row_cache
  end
end
