class LibrariesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  COLUMN_OPTIONS = {
    "page_name" => "Nota name",
    "workspace" => "Workspace",
    "created_by" => "Created by",
    "source" => "Source",
    "created_time" => "Created time",
    "last_edited_by" => "Last edited by",
    "last_edited_time" => "Last edited time",
    "last_visited_time" => "Last visited time"
  }.freeze
  DEFAULT_VISIBLE_COLUMNS = %w[page_name workspace created_by source last_edited_time last_visited_time].freeze
  TAB_OPTIONS = %w[all_documents recents favorites shared private].freeze
  SOURCE_OPTIONS = %w[all page meeting database].freeze
  VISIBILITY_OPTIONS = %w[all shared private].freeze
  SORT_OPTIONS = %w[last_edited_desc last_edited_asc created_desc created_asc page_name_asc page_name_desc].freeze
  VIEW_MODE_OPTIONS = %w[list thumbnails].freeze
  LIBRARY_PAGE_SIZE = 50
  SEARCHABLE_LIBRARY_SQL_COLUMNS = %w[title created_by last_edited_by workspace_name kind visibility].freeze
  FILTERABLE_LIBRARY_SQL_COLUMNS = {
    "page_name" => "title",
    "workspace" => "workspace_name",
    "created_by" => "created_by",
    "source" => "kind",
    "created_time" => "created_time_value",
    "last_edited_by" => "last_edited_by",
    "last_edited_time" => "last_edited_time_value",
    "last_visited_time" => "last_visited_time_value"
  }.freeze

  def show
    authorize @workspace, :show?

    @workspace_options = policy_scope(Workspace).select(:id, :name, :slug, :workspace_color, :updated_at).order(updated_at: :desc).to_a
    @workspace_filter_options = [ [ "All workspaces", "all" ] ] +
      @workspace_options.map { |workspace| [ workspace.name, workspace.slug ] }

    @workspace_filter = resolved_workspace_filter
    selected_workspaces = resolved_selected_workspaces
    selected_workspace_ids = selected_workspaces.map(&:id)

    @tab = resolved_tab
    @source_filter = resolved_source_filter
    @visibility_filter = resolved_visibility_filter
    @sort = resolved_sort
    @view_mode = resolved_view_mode
    @search_query = params[:q].to_s.strip
    @property_filter = resolved_property_filter
    @property_filter_value = params[:filter_value].to_s.strip
    @favorites_only = params[:favorites_only].to_s == "1"
    @column_options = COLUMN_OPTIONS
    @visible_columns = resolved_visible_columns

    page_scope = filtered_page_scope(selected_workspace_ids)
    database_scope = filtered_database_scope(selected_workspace_ids)

    if fast_path_applicable?
      owner_email_lookup = owner_email_by_workspace_id(selected_workspace_ids)
      favorite_lookup = favorite_lookup_for(selected_workspace_ids)
      last_visited_lookup = last_page_visit_store.each_value.with_object({}) { |page_id, memo| memo[page_id] = true }
      build_fast_library_rows(page_scope, database_scope, owner_email_lookup, favorite_lookup, last_visited_lookup)
    else
      build_filtered_library_rows_from_sql(page_scope, database_scope, selected_workspaces, selected_workspace_ids)
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def resolved_workspace_filter
    requested = params[:workspace_filter].to_s
    return "all" if requested.blank?
    return requested if requested == "all"
    return requested if @workspace_options.any? { |workspace| workspace.slug == requested }

    "all"
  end

  def resolved_selected_workspaces
    case @workspace_filter
    when "all"
      @workspace_options
    else
      selected = @workspace_options.find { |workspace| workspace.slug == @workspace_filter }
      selected ? [ selected ] : @workspace_options
    end
  end

  def resolved_tab
    requested = params[:tab].to_s
    TAB_OPTIONS.include?(requested) ? requested : "all_documents"
  end

  def resolved_source_filter
    requested = params[:source].to_s
    SOURCE_OPTIONS.include?(requested) ? requested : "all"
  end

  def resolved_visibility_filter
    requested = params[:visibility].to_s
    VISIBILITY_OPTIONS.include?(requested) ? requested : "all"
  end

  def resolved_sort
    requested = params[:sort].to_s
    SORT_OPTIONS.include?(requested) ? requested : "last_edited_desc"
  end

  def resolved_view_mode
    requested = params[:view_mode].to_s
    VIEW_MODE_OPTIONS.include?(requested) ? requested : "list"
  end

  def resolved_property_filter
    requested = params[:filter_property].to_s
    COLUMN_OPTIONS.key?(requested) ? requested : ""
  end

  def resolved_visible_columns
    requested = Array(params[:visible_columns]).map(&:to_s) & COLUMN_OPTIONS.keys
    requested = DEFAULT_VISIBLE_COLUMNS if requested.empty?
    requested |= [ "page_name" ]
    requested
  end

  def owner_email_by_workspace_id(workspace_ids)
    policy_scope(Membership)
      .where(workspace_id: workspace_ids, role: Membership.roles.fetch("owner"))
      .joins(:user)
      .order(:workspace_id, :created_at)
      .pluck(:workspace_id, "users.email")
      .each_with_object({}) do |(workspace_id, email), memo|
        memo[workspace_id] ||= email
      end
  end

  def favorite_lookup_for(workspace_ids)
    lookup = {}
    policy_scope(Favorite)
      .for_user(current_user)
      .where(workspace_id: workspace_ids)
      .pluck(:favoritable_type, :favoritable_id)
      .each do |favoritable_type, favoritable_id|
        lookup["#{favoritable_type}:#{favoritable_id}"] = true
      end
    lookup
  end

  def page_rows(scope, owner_email_lookup, favorite_lookup, last_visited_lookup)
    scope
      .to_a
      .filter_map do |page|
        meeting = page.page_kind == "meeting_note"
        creator_email = page.created_by&.email || owner_email_lookup[page.workspace_id] || "—"
        {
          record_type: "Page",
          record_id: page.id,
          kind: page.tab_child? ? "tab" : (meeting ? "meeting" : "page"),
          title: page.tab_child? ? page.tab_reference_title : page.title,
          icon: page.icon.presence || (meeting ? "🗒️" : "📄"),
          created_by: creator_email,
          created_time: page.created_at,
          last_edited_by: creator_email,
          last_edited_time: page.updated_at,
          last_visited_time: last_visited_lookup[page.id.to_s] ? page.updated_at : nil,
          visibility: page.permission_mode == "private_page" ? "private" : "shared",
          favorited: favorite_lookup["Page:#{page.id}"] == true,
          workspace_name: page.workspace.name,
          workspace: page.workspace,
          path: page_path(workspace_slug: page.workspace.slug, id: page.id)
        }
      end
  end

  def database_rows(scope, owner_email_lookup, favorite_lookup)
    scope
      .to_a
      .map do |database|
        creator_email = owner_email_lookup[database.workspace_id] || "—"
        {
          record_type: "Database",
          record_id: database.id,
          kind: database.tab_child? ? "grid_tab" : "database",
          title: database.tab_child? ? database.tab_reference_title : database.name,
          icon: database.icon.presence || "🗃️",
          created_by: database.created_by&.email || creator_email,
          created_time: database.created_at,
          last_edited_by: database.created_by&.email || creator_email,
          last_edited_time: database.updated_at,
          last_visited_time: nil,
          visibility: database.permission_mode == "private_database" ? "private" : "shared",
          favorited: favorite_lookup["Database:#{database.id}"] == true,
          workspace_name: database.workspace.name,
          workspace: database.workspace,
          path: database_path(workspace_slug: database.workspace.slug, id: database.id)
        }
      end
  end

  def filtered_page_scope(workspace_ids)
    scope = policy_scope(Page)
              .where(workspace_id: workspace_ids)
              .active
              .where.missing(:linked_database)
              .select(:id, :title, :icon, :created_by_id, :created_at, :updated_at, :workspace_id, :page_kind, :permission_mode, :parent_page_id)
              .includes(:workspace, :created_by, :parent_page)

    scope = apply_page_source_filter(scope)
    scope = apply_page_tab_filter(scope, workspace_ids)
    scope = apply_page_visibility_filter(scope)
    apply_page_favorites_filter(scope, workspace_ids)
  end

  def filtered_database_scope(workspace_ids)
    scope = policy_scope(Database)
              .where(workspace_id: workspace_ids)
              .active
              .select(:id, :name, :icon, :created_by_id, :created_at, :updated_at, :workspace_id, :permission_mode, :linked_page_id)
              .includes(:workspace, :created_by, linked_page: :parent_page)

    scope = apply_database_source_filter(scope)
    scope = apply_database_tab_filter(scope, workspace_ids)
    scope = apply_database_visibility_filter(scope)
    apply_database_favorites_filter(scope, workspace_ids)
  end

  def apply_page_source_filter(scope)
    case @source_filter
    when "database"
      scope.none
    when "meeting"
      scope.where(page_kind: "meeting_note")
    when "page"
      scope.where.not(page_kind: "meeting_note")
    else
      scope
    end
  end

  def apply_database_source_filter(scope)
    return scope if %w[all database].include?(@source_filter)

    scope.none
  end

  def apply_page_tab_filter(scope, workspace_ids)
    case @tab
    when "recents"
      scope.where("pages.updated_at >= ?", 1.week.ago)
    when "favorites"
      scope.where(id: favorite_ids_relation("Page", workspace_ids))
    when "shared"
      scope.where.not(permission_mode: Page.permission_modes.fetch("private_page"))
    when "private"
      scope.where(permission_mode: Page.permission_modes.fetch("private_page"))
    else
      scope
    end
  end

  def apply_database_tab_filter(scope, workspace_ids)
    case @tab
    when "recents"
      scope.where("databases.updated_at >= ?", 1.week.ago)
    when "favorites"
      scope.where(id: favorite_ids_relation("Database", workspace_ids))
    when "shared"
      scope.where.not(permission_mode: Database.permission_modes.fetch("private_database"))
    when "private"
      scope.where(permission_mode: Database.permission_modes.fetch("private_database"))
    else
      scope
    end
  end

  def apply_page_visibility_filter(scope)
    case @visibility_filter
    when "shared"
      scope.where.not(permission_mode: Page.permission_modes.fetch("private_page"))
    when "private"
      scope.where(permission_mode: Page.permission_modes.fetch("private_page"))
    else
      scope
    end
  end

  def apply_database_visibility_filter(scope)
    case @visibility_filter
    when "shared"
      scope.where.not(permission_mode: Database.permission_modes.fetch("private_database"))
    when "private"
      scope.where(permission_mode: Database.permission_modes.fetch("private_database"))
    else
      scope
    end
  end

  def apply_page_favorites_filter(scope, workspace_ids)
    return scope unless @favorites_only

    scope.where(id: favorite_ids_relation("Page", workspace_ids))
  end

  def apply_database_favorites_filter(scope, workspace_ids)
    return scope unless @favorites_only

    scope.where(id: favorite_ids_relation("Database", workspace_ids))
  end

  def favorite_ids_relation(favoritable_type, workspace_ids)
    policy_scope(Favorite)
      .for_user(current_user)
      .where(workspace_id: workspace_ids, favoritable_type: favoritable_type)
      .select(:favoritable_id)
  end

  def fast_path_applicable?
    @search_query.blank? && @property_filter.blank? && @property_filter_value.blank?
  end

  def build_filtered_library_rows_from_sql(page_scope, database_scope, selected_workspaces, selected_workspace_ids)
    @per_page = LIBRARY_PAGE_SIZE
    @current_page = resolved_page
    workspace_lookup = selected_workspaces.index_by(&:id)
    entries_sql = library_entries_union_sql(page_scope, database_scope, selected_workspace_ids)
    where_clause = filtered_library_where_clause

    @total_rows = ActiveRecord::Base.connection.select_value(
      Arel.sql("SELECT COUNT(*) FROM (#{entries_sql}) library_entries #{where_clause}")
    ).to_i
    @total_pages = [ (@total_rows.to_f / @per_page).ceil, 1 ].max
    @current_page = [ @current_page, @total_pages ].min

    offset = (@current_page - 1) * @per_page
    rows = ActiveRecord::Base.connection.select_all(
      Arel.sql(<<~SQL.squish)
        SELECT *
        FROM (#{entries_sql}) library_entries
        #{where_clause}
        ORDER BY #{filtered_library_order_clause}
        LIMIT #{@per_page}
        OFFSET #{offset}
      SQL
    )

    @library_rows = rows.map { |row| library_row_from_sql_result(row, workspace_lookup) }
    enrich_library_rows!(@library_rows)
    @page_start = @total_rows.zero? ? 0 : offset + 1
    @page_end = @total_rows.zero? ? 0 : offset + @library_rows.length
  end

  def build_fast_library_rows(page_scope, database_scope, owner_email_lookup, favorite_lookup, last_visited_lookup)
    @per_page = LIBRARY_PAGE_SIZE
    @total_rows = scoped_count(page_scope) + scoped_count(database_scope)
    @total_pages = [ (@total_rows.to_f / @per_page).ceil, 1 ].max
    @current_page = [ resolved_page, @total_pages ].min

    merge_limit = @current_page * @per_page
    @library_rows = []
    @library_rows.concat(
      page_rows(
        ordered_page_scope(page_scope).limit(merge_limit),
        owner_email_lookup,
        favorite_lookup,
        last_visited_lookup
      )
    )
    @library_rows.concat(
      database_rows(
        ordered_database_scope(database_scope).limit(merge_limit),
        owner_email_lookup,
        favorite_lookup
      )
    )

    apply_sort!

    start_index = (@current_page - 1) * @per_page
    @library_rows = @library_rows.slice(start_index, @per_page) || []
    enrich_library_rows!(@library_rows)
    @page_start = @total_rows.zero? ? 0 : start_index + 1
    @page_end = @total_rows.zero? ? 0 : start_index + @library_rows.length
  end

  def ordered_page_scope(scope)
    ordered_library_scope(scope, table_name: "pages", name_column: "title")
  end

  def ordered_database_scope(scope)
    ordered_library_scope(scope, table_name: "databases", name_column: "name")
  end

  def ordered_library_scope(scope, table_name:, name_column:)
    case @sort
    when "last_edited_asc"
      scope.order(updated_at: :asc, id: :asc)
    when "created_desc"
      scope.order(created_at: :desc, id: :desc)
    when "created_asc"
      scope.order(created_at: :asc, id: :asc)
    when "page_name_asc"
      scope.order(Arel.sql("LOWER(#{table_name}.#{name_column}) ASC"), id: :asc)
    when "page_name_desc"
      scope.order(Arel.sql("LOWER(#{table_name}.#{name_column}) DESC"), id: :desc)
    else
      scope.order(updated_at: :desc, id: :desc)
    end
  end

  def library_entries_union_sql(page_scope, database_scope, workspace_ids)
    owner_email_sql = owner_email_subquery_sql(workspace_ids)
    visited_page_ids_sql = visited_page_ids_sql_list
    timezone_name = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)

    <<~SQL.squish
      #{page_library_entries_sql(page_scope, owner_email_sql, visited_page_ids_sql, timezone_name)}
      UNION ALL
      #{database_library_entries_sql(database_scope, owner_email_sql, timezone_name)}
    SQL
  end

  def page_library_entries_sql(scope, owner_email_sql, visited_page_ids_sql, timezone_name)
    scope
      .except(:select, :includes, :preload, :eager_load, :order)
      .joins("INNER JOIN workspaces ON workspaces.id = pages.workspace_id")
      .joins("LEFT JOIN users AS created_users ON created_users.id = pages.created_by_id")
      .joins("LEFT JOIN pages AS parent_pages ON parent_pages.id = pages.parent_page_id")
      .joins("LEFT JOIN (#{owner_email_sql}) AS workspace_owner_emails ON workspace_owner_emails.workspace_id = pages.workspace_id")
      .select(<<~SQL.squish)
        'Page' AS record_type,
        pages.id AS record_id,
        pages.workspace_id AS workspace_id,
        workspaces.slug AS workspace_slug,
        workspaces.name AS workspace_name,
        CASE
          WHEN pages.parent_page_id IS NOT NULL AND parent_pages.title IS NOT NULL AND parent_pages.title <> ''
            THEN parent_pages.title || ' / ' || pages.title
          ELSE pages.title
        END AS title,
        pages.icon AS icon,
        CASE
          WHEN pages.parent_page_id IS NOT NULL THEN 'tab'
          WHEN pages.page_kind = 'meeting_note' THEN 'meeting'
          ELSE 'page'
        END AS kind,
        COALESCE(created_users.email, workspace_owner_emails.owner_email, '—') AS created_by,
        pages.created_at AS created_time,
        TO_CHAR(timezone(#{timezone_name}, pages.created_at), 'YYYY-MM-DD HH24:MI') AS created_time_value,
        COALESCE(created_users.email, workspace_owner_emails.owner_email, '—') AS last_edited_by,
        pages.updated_at AS last_edited_time,
        TO_CHAR(timezone(#{timezone_name}, pages.updated_at), 'YYYY-MM-DD HH24:MI') AS last_edited_time_value,
        CASE
          WHEN pages.id IN (#{visited_page_ids_sql}) THEN pages.updated_at
          ELSE NULL
        END AS last_visited_time,
        CASE
          WHEN pages.id IN (#{visited_page_ids_sql})
            THEN TO_CHAR(timezone(#{timezone_name}, pages.updated_at), 'YYYY-MM-DD HH24:MI')
          ELSE ''
        END AS last_visited_time_value,
        CASE
          WHEN pages.permission_mode = #{Page.permission_modes.fetch("private_page")} THEN 'private'
          ELSE 'shared'
        END AS visibility,
        #{favorite_exists_sql(favoritable_type: "Page", table_name: "pages", id_column: "pages.id")} AS favorited
      SQL
      .to_sql
  end

  def database_library_entries_sql(scope, owner_email_sql, timezone_name)
    scope
      .except(:select, :includes, :preload, :eager_load, :order)
      .joins("INNER JOIN workspaces ON workspaces.id = databases.workspace_id")
      .joins("LEFT JOIN users AS created_users ON created_users.id = databases.created_by_id")
      .joins("LEFT JOIN pages AS linked_pages ON linked_pages.id = databases.linked_page_id")
      .joins("LEFT JOIN pages AS parent_pages ON parent_pages.id = linked_pages.parent_page_id")
      .joins("LEFT JOIN (#{owner_email_sql}) AS workspace_owner_emails ON workspace_owner_emails.workspace_id = databases.workspace_id")
      .select(<<~SQL.squish)
        'Database' AS record_type,
        databases.id AS record_id,
        databases.workspace_id AS workspace_id,
        workspaces.slug AS workspace_slug,
        workspaces.name AS workspace_name,
        CASE
          WHEN linked_pages.parent_page_id IS NOT NULL THEN
            CASE
              WHEN parent_pages.title IS NOT NULL AND parent_pages.title <> ''
                THEN parent_pages.title || ' / ' || linked_pages.title
              WHEN linked_pages.title IS NOT NULL AND linked_pages.title <> ''
                THEN linked_pages.title
              ELSE databases.name
            END
          ELSE databases.name
        END AS title,
        databases.icon AS icon,
        CASE
          WHEN linked_pages.parent_page_id IS NOT NULL THEN 'grid_tab'
          ELSE 'database'
        END AS kind,
        COALESCE(created_users.email, workspace_owner_emails.owner_email, '—') AS created_by,
        databases.created_at AS created_time,
        TO_CHAR(timezone(#{timezone_name}, databases.created_at), 'YYYY-MM-DD HH24:MI') AS created_time_value,
        COALESCE(created_users.email, workspace_owner_emails.owner_email, '—') AS last_edited_by,
        databases.updated_at AS last_edited_time,
        TO_CHAR(timezone(#{timezone_name}, databases.updated_at), 'YYYY-MM-DD HH24:MI') AS last_edited_time_value,
        NULL::timestamp AS last_visited_time,
        ''::text AS last_visited_time_value,
        CASE
          WHEN databases.permission_mode = #{Database.permission_modes.fetch("private_database")} THEN 'private'
          ELSE 'shared'
        END AS visibility,
        #{favorite_exists_sql(favoritable_type: "Database", table_name: "databases", id_column: "databases.id")} AS favorited
      SQL
      .to_sql
  end

  def owner_email_subquery_sql(workspace_ids)
    policy_scope(Membership)
      .joins(:user)
      .where(workspace_id: workspace_ids, role: Membership.roles.fetch("owner"))
      .select("DISTINCT ON (memberships.workspace_id) memberships.workspace_id, users.email AS owner_email")
      .order("memberships.workspace_id ASC, memberships.created_at ASC")
      .to_sql
  end

  def favorite_exists_sql(favoritable_type:, table_name:, id_column:)
    <<~SQL.squish
      EXISTS (
        SELECT 1
        FROM favorites
        WHERE favorites.user_id = #{ActiveRecord::Base.connection.quote(current_user.id)}
          AND favorites.workspace_id = #{table_name}.workspace_id
          AND favorites.favoritable_type = #{ActiveRecord::Base.connection.quote(favoritable_type)}
          AND favorites.favoritable_id = #{id_column}
      )
    SQL
  end

  def visited_page_ids_sql_list
    visited_ids = last_page_visit_store.values.filter_map { |page_id| Integer(page_id, exception: false) }
    visited_ids.presence&.join(", ") || "NULL"
  end

  def filtered_library_where_clause
    conditions = []

    if @search_query.present?
      pattern = quoted_like_pattern(@search_query)
      conditions << SEARCHABLE_LIBRARY_SQL_COLUMNS.map { |column| "LOWER(COALESCE(#{column}, '')) LIKE #{pattern}" }.join(" OR ").prepend("(").concat(")")
    end

    if @property_filter.present? && @property_filter_value.present?
      column = FILTERABLE_LIBRARY_SQL_COLUMNS.fetch(@property_filter)
      conditions << "LOWER(COALESCE(#{column}, '')) LIKE #{quoted_like_pattern(@property_filter_value)}"
    end

    conditions.present? ? "WHERE #{conditions.join(' AND ')}" : ""
  end

  def quoted_like_pattern(value)
    ActiveRecord::Base.connection.quote("%#{ActiveRecord::Base.sanitize_sql_like(value.downcase)}%")
  end

  def filtered_library_order_clause
    case @sort
    when "last_edited_asc"
      "last_edited_time ASC, LOWER(title) ASC, record_type ASC, record_id ASC"
    when "created_desc"
      "created_time DESC, LOWER(title) ASC, record_type ASC, record_id ASC"
    when "created_asc"
      "created_time ASC, LOWER(title) ASC, record_type ASC, record_id ASC"
    when "page_name_asc"
      "LOWER(title) ASC, record_type ASC, record_id ASC"
    when "page_name_desc"
      "LOWER(title) DESC, record_type DESC, record_id DESC"
    else
      "last_edited_time DESC, LOWER(title) ASC, record_type ASC, record_id ASC"
    end
  end

  def library_row_from_sql_result(row, workspace_lookup)
    workspace_id = row.fetch("workspace_id").to_s
    workspace_slug = row.fetch("workspace_slug")
    record_type = row.fetch("record_type")
    record_id = row.fetch("record_id").to_s
    kind = row.fetch("kind")
    workspace = workspace_lookup[workspace_id] || Workspace.new(id: workspace_id, slug: workspace_slug, name: row.fetch("workspace_name"))

    {
      record_type: record_type,
      record_id: record_id,
      kind: kind,
      title: row.fetch("title"),
      icon: library_row_icon_for(record_type, kind, row["icon"]),
      created_by: row.fetch("created_by"),
      created_time: cast_library_timestamp(row["created_time"]),
      last_edited_by: row.fetch("last_edited_by"),
      last_edited_time: cast_library_timestamp(row["last_edited_time"]),
      last_visited_time: cast_library_timestamp(row["last_visited_time"]),
      visibility: row.fetch("visibility"),
      favorited: ActiveModel::Type::Boolean.new.cast(row["favorited"]),
      workspace_name: row.fetch("workspace_name"),
      workspace: workspace,
      path: library_row_path_for(record_type, workspace_slug, record_id)
    }
  end

  def enrich_library_rows!(rows)
    return if rows.blank?

    page_ids = rows.filter_map { |row| row[:record_id] if row[:record_type] == "Page" }.uniq
    database_ids = rows.filter_map { |row| row[:record_id] if row[:record_type] == "Database" }.uniq

    pages_by_id = Page.where(id: page_ids).includes(:parent_page).with_attached_cover_image.index_by(&:id)
    databases_by_id = Database.where(id: database_ids).includes(:linked_page).with_attached_cover_image.index_by(&:id)
    linked_page_ids = databases_by_id.values.filter_map(&:linked_page_id).uniq
    linked_pages_by_id = Page.where(id: linked_page_ids).includes(:parent_page).with_attached_cover_image.index_by(&:id)

    rows.each do |row|
      record = row[:record_type] == "Database" ? databases_by_id[row[:record_id]] : pages_by_id[row[:record_id]]
      linked_page = record.is_a?(Database) ? linked_pages_by_id[record.linked_page_id] : nil
      icon_value = if record.is_a?(Database)
        record.icon.presence || linked_page&.icon.presence
      else
        record&.icon.presence
      end

      row[:icon] = library_row_icon_for(row[:record_type], row[:kind], icon_value.presence || row[:icon])
      row[:document_type_label] = library_document_type_label(row[:kind])
      row[:description] = library_row_description(record)
      row[:cover_record] = library_cover_record(record, linked_page:)
      row[:workspace_color] = row[:workspace]&.display_color || Workspace::DEFAULT_COLOR
    end
  end

  def library_document_type_label(kind)
    case kind
    when "database"
      "Grid"
    when "grid_tab"
      "Grid tab"
    when "tab"
      "Tab"
    when "meeting"
      "Meeting"
    else
      "Nota"
    end
  end

  def library_row_description(record)
    case record
    when Database
      record.description.to_s.strip.presence
    else
      nil
    end
  end

  def library_cover_record(record, linked_page: nil)
    return nil if record.blank?

    if record.is_a?(Database)
      return linked_page if linked_page&.cover?
      return record if record.cover?
      return linked_page if linked_page.present?
    end

    return record if record.respond_to?(:cover?) && record.cover?

    nil
  end

  def library_row_icon_for(record_type, kind, value)
    return value if value.present?
    return "🗃️" if record_type == "Database"
    return "🗒️" if kind == "meeting"

    "📄"
  end

  def library_row_path_for(record_type, workspace_slug, record_id)
    if record_type == "Database"
      database_path(workspace_slug: workspace_slug, id: record_id)
    else
      page_path(workspace_slug: workspace_slug, id: record_id)
    end
  end

  def scoped_count(scope)
    scope.except(:select, :includes, :preload, :eager_load, :order).count(:all)
  end

  def apply_sort!
    case @sort
    when "last_edited_asc"
      @library_rows.sort_by! { |row| row[:last_edited_time] || Time.at(0) }
    when "created_desc"
      @library_rows.sort_by! { |row| row[:created_time] || Time.at(0) }.reverse!
    when "created_asc"
      @library_rows.sort_by! { |row| row[:created_time] || Time.at(0) }
    when "page_name_asc"
      @library_rows.sort_by! { |row| row[:title].to_s.downcase }
    when "page_name_desc"
      @library_rows.sort_by! { |row| row[:title].to_s.downcase }.reverse!
    else
      @library_rows.sort_by! { |row| row[:last_edited_time] || Time.at(0) }.reverse!
    end
  end

  def resolved_page
    requested = params[:page].to_i
    requested.positive? ? requested : 1
  end

  def cast_library_timestamp(value)
    return value.in_time_zone if value.respond_to?(:in_time_zone)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  end
end
