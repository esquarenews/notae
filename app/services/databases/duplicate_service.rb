module Databases
  class DuplicateService
    class << self
      def call(database:, created_by:, name: nil)
        new(database:, created_by:, name:).call
      end
    end

    def initialize(database:, created_by:, name: nil)
      @database = database
      @workspace = database.workspace
      @created_by = created_by
      @requested_name = name
    end

    def call
      ActiveRecord::Base.transaction do
        duplicate_database = build_duplicate_database!
        property_id_map = duplicate_properties!(target_database: duplicate_database)
        duplicate_rows!(target_database: duplicate_database, property_id_map: property_id_map)
        duplicate_views!(target_database: duplicate_database, property_id_map: property_id_map)
        ensure_default_view!(duplicate_database)
        duplicate_database
      end
    end

    private

    attr_reader :database, :workspace, :created_by, :requested_name

    def build_duplicate_database!
      duplicate = workspace.databases.create!(
        name: duplicate_name,
        description: database.description,
        icon: database.icon,
        cover_preset_key: database.cover_preset_key,
        cover_focal_y: database.cover_focal_y,
        linked_page: database.linked_page,
        small_text: database.small_text,
        font_style: database.font_style,
        locked: false
      )
      duplicate.cover_image.attach(database.cover_image.blob) if database.cover_image.attached?
      duplicate
    end

    def duplicate_properties!(target_database:)
      policy_scope = database.db_properties.order(:position, :created_at)
      policy_scope.each_with_object({}) do |db_property, property_id_map|
        duplicated_property = target_database.db_properties.create!(
          workspace: workspace,
          name: db_property.name,
          property_type: db_property.property_type,
          position: db_property.position
        )
        property_id_map[db_property.id.to_s] = duplicated_property.id.to_s
      end
    end

    def duplicate_rows!(target_database:, property_id_map:)
      source_rows = database.db_rows.active.order(:position, :created_at).includes(:db_cells)
      source_rows.each do |source_row|
        duplicated_row = target_database.db_rows.create!(
          workspace: workspace,
          title: source_row.title,
          position: source_row.position,
          linked_page: source_row.linked_page
        )

        source_row.db_cells.each do |source_cell|
          mapped_property_id = property_id_map[source_cell.db_property_id.to_s]
          next if mapped_property_id.blank?

          duplicated_row.db_cells.create!(
            workspace: workspace,
            db_property_id: mapped_property_id,
            value_text: source_cell.value_text
          )
        end

        duplicated_row.sync_data_from_cells!
      end
    end

    def duplicate_views!(target_database:, property_id_map:)
      source_views = database.database_views.ordered.to_a
      source_views.each do |source_view|
        target_database.database_views.create!(
          workspace: workspace,
          created_by: created_by,
          name: source_view.name,
          view_type: source_view.view_type,
          default: source_view.default?,
          config_json: remap_view_config(source_view.config_json, property_id_map)
        )
      end
    end

    def ensure_default_view!(target_database)
      return if target_database.database_views.where(default: true).exists?

      target_database.database_views.ordered.first&.set_as_default!
    end

    def remap_view_config(config_json, property_id_map)
      config = config_json.to_h.deep_dup

      %w[
        sort_property_id
        filter_property_id
        group_property_id
        date_property_id
        conditional_color_property_id
      ].each do |config_key|
        next unless config[config_key].present?

        mapped_value = property_id_map[config[config_key].to_s]
        mapped_value.present? ? config[config_key] = mapped_value : config.delete(config_key)
      end

      if config["visible_property_ids"].present?
        mapped_ids = Array(config["visible_property_ids"])
                       .map { |property_id| property_id_map[property_id.to_s] }
                       .compact
                       .uniq
        mapped_ids.empty? ? config.delete("visible_property_ids") : config["visible_property_ids"] = mapped_ids
      end

      config.compact
    end

    def duplicate_name
      base_name = requested_name.to_s.strip.presence || "#{database.name} (copy)"
      return base_name unless workspace.databases.exists?(name: base_name)

      suffix = 2
      loop do
        candidate_name = "#{base_name} #{suffix}"
        return candidate_name unless workspace.databases.exists?(name: candidate_name)

        suffix += 1
      end
    end
  end
end
