module Databases
  class RowWindowQueryService
    DEFAULT_PER_PAGE = ENV.fetch("NOTAE_DATABASE_ROWS_PER_PAGE", 25).to_i.clamp(10, 100)

    Result = Struct.new(:rows, :total_count, :page, :per_page, :total_pages, :paginated?, keyword_init: true)

    def initialize(scope:, sort_property:, sort_by_title: false, sort_direction:, sort_mode: "standard", filter_property:, filter_value:, filter_operator:, view_type:, page:)
      @scope = scope
      @sort_property = sort_property
      @sort_by_title = sort_by_title
      @sort_direction = sort_direction == "desc" ? "desc" : "asc"
      @sort_mode = sort_mode.to_s
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
      bound_value = normalized_filter_value(@filter_property, @filter_value)
      return scope unless bound_value.present?

      if @filter_property.numeric_like?
        apply_number_filter(scope, bound_value)
      elsif @filter_property.date?
        apply_date_filter(scope, bound_value)
      elsif @filter_property.checkbox?
        apply_checkbox_filter(scope, bound_value)
      else
        apply_text_filter(scope, bound_value)
      end
    end

    def apply_sort(scope)
      if @sort_by_title
        if @sort_mode == "calendar"
          calendar_rank_sql = calendar_sort_rank_sql("db_rows.title")
          null_order_sql = Arel.sql("CASE WHEN #{calendar_rank_sql} IS NULL THEN 1 ELSE 0 END ASC")
          value_order_sql =
            @sort_direction == "desc" ?
              Arel.sql("#{calendar_rank_sql} DESC") :
              Arel.sql("#{calendar_rank_sql} ASC")
          fallback_title_order_sql =
            @sort_direction == "desc" ?
              Arel.sql("LOWER(db_rows.title) DESC") :
              Arel.sql("LOWER(db_rows.title) ASC")

          return scope.order(null_order_sql, value_order_sql, fallback_title_order_sql, :created_at)
        end

        title_order_sql = @sort_direction == "desc" ? Arel.sql("LOWER(db_rows.title) DESC") : Arel.sql("LOWER(db_rows.title) ASC")
        return scope.order(title_order_sql, :created_at)
      end

      return scope.order(:position, :created_at) unless @sort_property.present?

      alias_name = "sort_cells"
      scope = join_cell(scope, alias_name, @sort_property.id)

      if calendar_sortable?
        calendar_rank_sql = calendar_sort_rank_sql("#{alias_name}.value_text")
        null_order_sql = Arel.sql("CASE WHEN #{calendar_rank_sql} IS NULL THEN 1 ELSE 0 END ASC")
        value_order_sql =
          @sort_direction == "desc" ?
            Arel.sql("#{calendar_rank_sql} DESC") :
            Arel.sql("#{calendar_rank_sql} ASC")
        fallback_text_order_sql =
          @sort_direction == "desc" ?
            Arel.sql("LOWER(NULLIF(TRIM(#{alias_name}.value_text), '')) DESC") :
            Arel.sql("LOWER(NULLIF(TRIM(#{alias_name}.value_text), '')) ASC")

        return scope.order(null_order_sql, value_order_sql, fallback_text_order_sql, Arel.sql("LOWER(db_rows.title) ASC"), :created_at)
      end

      null_order_sql, value_order_sql =
        if @sort_property.numeric_like?
          [
            Arel.sql("CASE WHEN CAST(NULLIF(TRIM(sort_cells.value_text), '') AS REAL) IS NULL THEN 1 ELSE 0 END ASC"),
            @sort_direction == "desc" ?
              Arel.sql("CAST(NULLIF(TRIM(sort_cells.value_text), '') AS REAL) DESC") :
              Arel.sql("CAST(NULLIF(TRIM(sort_cells.value_text), '') AS REAL) ASC")
          ]
        elsif @sort_property.date?
          [
            Arel.sql("CASE WHEN DATE(NULLIF(TRIM(sort_cells.value_text), '')) IS NULL THEN 1 ELSE 0 END ASC"),
            @sort_direction == "desc" ?
              Arel.sql("DATE(NULLIF(TRIM(sort_cells.value_text), '')) DESC") :
              Arel.sql("DATE(NULLIF(TRIM(sort_cells.value_text), '')) ASC")
          ]
        elsif @sort_property.checkbox?
          [
            Arel.sql("CASE WHEN CASE WHEN LOWER(COALESCE(sort_cells.value_text, '')) IN ('1', 'true', 'yes', 'on') THEN 1 WHEN LOWER(COALESCE(sort_cells.value_text, '')) IN ('0', 'false', 'no', 'off') THEN 0 ELSE NULL END IS NULL THEN 1 ELSE 0 END ASC"),
            @sort_direction == "desc" ?
              Arel.sql("CASE WHEN LOWER(COALESCE(sort_cells.value_text, '')) IN ('1', 'true', 'yes', 'on') THEN 1 WHEN LOWER(COALESCE(sort_cells.value_text, '')) IN ('0', 'false', 'no', 'off') THEN 0 ELSE NULL END DESC") :
              Arel.sql("CASE WHEN LOWER(COALESCE(sort_cells.value_text, '')) IN ('1', 'true', 'yes', 'on') THEN 1 WHEN LOWER(COALESCE(sort_cells.value_text, '')) IN ('0', 'false', 'no', 'off') THEN 0 ELSE NULL END ASC")
          ]
        else
          [
            Arel.sql("CASE WHEN LOWER(NULLIF(TRIM(sort_cells.value_text), '')) IS NULL THEN 1 ELSE 0 END ASC"),
            @sort_direction == "desc" ?
              Arel.sql("LOWER(NULLIF(TRIM(sort_cells.value_text), '')) DESC") :
              Arel.sql("LOWER(NULLIF(TRIM(sort_cells.value_text), '')) ASC")
          ]
        end

      scope.order(null_order_sql, value_order_sql, Arel.sql("LOWER(db_rows.title) ASC"), :created_at)
    end

    def calendar_sortable?
      return false unless @sort_mode == "calendar"
      return false if @sort_property.blank?

      !@sort_property.numeric_like? && !@sort_property.date? && !@sort_property.checkbox?
    end

    def calendar_sort_rank_sql(column_sql)
      normalized_value_sql = "LOWER(NULLIF(TRIM(#{column_sql}), ''))"

      <<~SQL.squish
        CASE #{normalized_value_sql}
          WHEN 'monday' THEN 1
          WHEN 'mon' THEN 1
          WHEN 'tuesday' THEN 2
          WHEN 'tue' THEN 2
          WHEN 'tues' THEN 2
          WHEN 'wednesday' THEN 3
          WHEN 'wed' THEN 3
          WHEN 'thursday' THEN 4
          WHEN 'thu' THEN 4
          WHEN 'thur' THEN 4
          WHEN 'thurs' THEN 4
          WHEN 'friday' THEN 5
          WHEN 'fri' THEN 5
          WHEN 'saturday' THEN 6
          WHEN 'sat' THEN 6
          WHEN 'sunday' THEN 7
          WHEN 'sun' THEN 7
          WHEN 'january' THEN 101
          WHEN 'jan' THEN 101
          WHEN 'february' THEN 102
          WHEN 'feb' THEN 102
          WHEN 'march' THEN 103
          WHEN 'mar' THEN 103
          WHEN 'april' THEN 104
          WHEN 'apr' THEN 104
          WHEN 'may' THEN 105
          WHEN 'june' THEN 106
          WHEN 'jun' THEN 106
          WHEN 'july' THEN 107
          WHEN 'jul' THEN 107
          WHEN 'august' THEN 108
          WHEN 'aug' THEN 108
          WHEN 'september' THEN 109
          WHEN 'sep' THEN 109
          WHEN 'sept' THEN 109
          WHEN 'october' THEN 110
          WHEN 'oct' THEN 110
          WHEN 'november' THEN 111
          WHEN 'nov' THEN 111
          WHEN 'december' THEN 112
          WHEN 'dec' THEN 112
          ELSE NULL
        END
      SQL
    end

    def apply_text_filter(scope, bound_value)
      case @filter_operator
      when "neq"
        scope.where("LOWER(NULLIF(TRIM(filter_cells.value_text), '')) IS NULL OR LOWER(NULLIF(TRIM(filter_cells.value_text), '')) != ?", bound_value)
      else
        scope.where("LOWER(NULLIF(TRIM(filter_cells.value_text), '')) = ?", bound_value)
      end
    end

    def apply_number_filter(scope, bound_value)
      case @filter_operator
      when "neq"
        scope.where("CAST(NULLIF(TRIM(filter_cells.value_text), '') AS REAL) IS NULL OR CAST(NULLIF(TRIM(filter_cells.value_text), '') AS REAL) != ?", bound_value)
      when "before"
        scope.where("CAST(NULLIF(TRIM(filter_cells.value_text), '') AS REAL) < ?", bound_value)
      when "after"
        scope.where("CAST(NULLIF(TRIM(filter_cells.value_text), '') AS REAL) > ?", bound_value)
      else
        scope.where("CAST(NULLIF(TRIM(filter_cells.value_text), '') AS REAL) = ?", bound_value)
      end
    end

    def apply_date_filter(scope, bound_value)
      case @filter_operator
      when "neq"
        scope.where("DATE(NULLIF(TRIM(filter_cells.value_text), '')) IS NULL OR DATE(NULLIF(TRIM(filter_cells.value_text), '')) != ?", bound_value)
      when "before"
        scope.where("DATE(NULLIF(TRIM(filter_cells.value_text), '')) < ?", bound_value)
      when "after"
        scope.where("DATE(NULLIF(TRIM(filter_cells.value_text), '')) > ?", bound_value)
      else
        scope.where("DATE(NULLIF(TRIM(filter_cells.value_text), '')) = ?", bound_value)
      end
    end

    def apply_checkbox_filter(scope, bound_value)
      case @filter_operator
      when "neq"
        scope.where("CASE WHEN LOWER(COALESCE(filter_cells.value_text, '')) IN ('1', 'true', 'yes', 'on') THEN 1 WHEN LOWER(COALESCE(filter_cells.value_text, '')) IN ('0', 'false', 'no', 'off') THEN 0 ELSE NULL END IS NULL OR CASE WHEN LOWER(COALESCE(filter_cells.value_text, '')) IN ('1', 'true', 'yes', 'on') THEN 1 WHEN LOWER(COALESCE(filter_cells.value_text, '')) IN ('0', 'false', 'no', 'off') THEN 0 ELSE NULL END != ?", bound_value)
      else
        scope.where("CASE WHEN LOWER(COALESCE(filter_cells.value_text, '')) IN ('1', 'true', 'yes', 'on') THEN 1 WHEN LOWER(COALESCE(filter_cells.value_text, '')) IN ('0', 'false', 'no', 'off') THEN 0 ELSE NULL END = ?", bound_value)
      end
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

    def normalized_filter_value(property, raw_value)
      case property.property_type
      when "number", "progress"
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
