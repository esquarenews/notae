module Databases
  class RowWindowQueryService
    DEFAULT_PER_PAGE = 50

    Result = Struct.new(:rows, :total_count, :page, :per_page, :total_pages, :paginated?, keyword_init: true)

    def initialize(scope:, sort_property:, sort_direction:, filter_property:, filter_value:, filter_operator:, view_type:, page:)
      @scope = scope
      @sort_property = sort_property
      @sort_direction = sort_direction == "desc" ? "desc" : "asc"
      @filter_property = filter_property
      @filter_value = filter_value.to_s.strip
      @filter_operator = filter_operator.to_s
      @view_type = view_type.to_s
      @page = page.to_i > 0 ? page.to_i : 1
    end

    def call
      relation = @scope.includes(:linked_page)
      relation = apply_filter(relation)
      relation = apply_sort(relation)

      total_count = relation.count
      total_pages = paginate? ? [ (total_count.to_f / per_page).ceil, 1 ].max : 1
      current_page = paginate? ? [ @page, total_pages ].min : 1
      rows = if paginate?
        relation.limit(per_page).offset((current_page - 1) * per_page).to_a
      else
        relation.to_a
      end

      Result.new(
        rows: rows,
        total_count: total_count,
        page: current_page,
        per_page: per_page,
        total_pages: total_pages,
        paginated?: paginate?
      )
    end

    private

    def paginate?
      %w[table list].include?(@view_type)
    end

    def per_page
      DEFAULT_PER_PAGE
    end

    def apply_filter(scope)
      return scope unless @filter_property.present? && @filter_value.present?

      alias_name = "filter_cells"
      scope = join_cell(scope, alias_name, @filter_property.id)
      sql_value = sql_value_expression(@filter_property, alias_name)
      bound_value = normalized_filter_value(@filter_property, @filter_value)
      return scope unless bound_value.present?

      case @filter_operator
      when "neq"
        scope.where("#{sql_value} IS NULL OR #{sql_value} != ?", bound_value)
      when "before"
        return scope unless @filter_property.number? || @filter_property.date?

        scope.where("#{sql_value} < ?", bound_value)
      when "after"
        return scope unless @filter_property.number? || @filter_property.date?

        scope.where("#{sql_value} > ?", bound_value)
      else
        scope.where("#{sql_value} = ?", bound_value)
      end
    end

    def apply_sort(scope)
      return scope.order(:position, :created_at) unless @sort_property.present?

      alias_name = "sort_cells"
      scope = join_cell(scope, alias_name, @sort_property.id)
      sql_value = sql_value_expression(@sort_property, alias_name)
      scope.order(
        Arel.sql("CASE WHEN #{sql_value} IS NULL THEN 1 ELSE 0 END ASC"),
        Arel.sql("#{sql_value} #{@sort_direction.upcase}"),
        Arel.sql("LOWER(db_rows.title) ASC"),
        :created_at
      )
    end

    def join_cell(scope, alias_name, property_id)
      scope.joins(
        sanitize_sql_array(
          [
            "LEFT JOIN db_cells #{alias_name} ON #{alias_name}.db_row_id = db_rows.id AND #{alias_name}.db_property_id = ?",
            property_id
          ]
        )
      )
    end

    def sql_value_expression(property, alias_name)
      case property.property_type
      when "number"
        "CAST(NULLIF(TRIM(#{alias_name}.value_text), '') AS REAL)"
      when "date"
        "DATE(NULLIF(TRIM(#{alias_name}.value_text), ''))"
      when "checkbox"
        truthy = DbCell::TRUTHY_VALUES.map { |value| ActiveRecord::Base.connection.quote(value) }.join(", ")
        falsy = DbCell::FALSY_VALUES.map { |value| ActiveRecord::Base.connection.quote(value) }.join(", ")
        <<~SQL.squish
          CASE
            WHEN LOWER(COALESCE(#{alias_name}.value_text, '')) IN (#{truthy}) THEN 1
            WHEN LOWER(COALESCE(#{alias_name}.value_text, '')) IN (#{falsy}) THEN 0
            ELSE NULL
          END
        SQL
      else
        "LOWER(NULLIF(TRIM(#{alias_name}.value_text), ''))"
      end
    end

    def normalized_filter_value(property, raw_value)
      case property.property_type
      when "number"
        Float(raw_value)
      when "date"
        Date.parse(raw_value).iso8601
      when "checkbox"
        normalized = raw_value.to_s.strip.downcase
        return 1 if DbCell::TRUTHY_VALUES.include?(normalized)
        return 0 if DbCell::FALSY_VALUES.include?(normalized)

        nil
      else
        raw_value.to_s.strip.downcase.presence
      end
    rescue ArgumentError
      nil
    end

    def sanitize_sql_array(args)
      ActiveRecord::Base.send(:sanitize_sql_array, args)
    end
  end
end
