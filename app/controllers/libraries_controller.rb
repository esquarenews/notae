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
  LIBRARY_PAGE_SIZE = 50

  def show
    authorize @workspace, :show?

    @workspace_options = policy_scope(Workspace).order(updated_at: :desc).to_a
    @workspace_filter_options = [ [ "All workspaces", "all" ] ] +
      @workspace_options.map { |workspace| [ workspace.name, workspace.slug ] }

    @workspace_filter = resolved_workspace_filter
    selected_workspaces = resolved_selected_workspaces
    selected_workspace_ids = selected_workspaces.map(&:id)

    @tab = resolved_tab
    @source_filter = resolved_source_filter
    @visibility_filter = resolved_visibility_filter
    @sort = resolved_sort
    @search_query = params[:q].to_s.strip
    @property_filter = resolved_property_filter
    @property_filter_value = params[:filter_value].to_s.strip
    @favorites_only = params[:favorites_only].to_s == "1"
    @column_options = COLUMN_OPTIONS
    @visible_columns = resolved_visible_columns

    owner_email_lookup = owner_email_by_workspace_id(selected_workspace_ids)
    favorite_lookup = favorite_lookup_for(selected_workspace_ids)
    last_visited_ids = session.fetch("notae_last_page_visits", {}).values.map(&:to_s)

    @library_rows = []
    @library_rows.concat(page_rows(selected_workspace_ids, owner_email_lookup, favorite_lookup, last_visited_ids))
    @library_rows.concat(database_rows(selected_workspace_ids, owner_email_lookup, favorite_lookup))

    apply_filters!
    apply_sort!
    apply_pagination!
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
      .includes(:user)
      .order(:created_at)
      .each_with_object({}) do |membership, memo|
        memo[membership.workspace_id] ||= membership.user.email
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

  def page_rows(workspace_ids, owner_email_lookup, favorite_lookup, last_visited_ids)
    policy_scope(Page)
      .where(workspace_id: workspace_ids)
      .active
      .includes(:workspace, :created_by)
      .to_a
      .map do |page|
        meeting = page.page_kind == "meeting_note"
        creator_email = page.created_by&.email || owner_email_lookup[page.workspace_id] || "—"
        {
          kind: meeting ? "meeting" : "page",
          title: page.title,
          icon: page.icon.presence || (meeting ? "🗒️" : "📄"),
          created_by: creator_email,
          created_time: page.created_at,
          last_edited_by: creator_email,
          last_edited_time: page.updated_at,
          last_visited_time: last_visited_ids.include?(page.id.to_s) ? page.updated_at : nil,
          visibility: page.permission_mode == "private_page" ? "private" : "shared",
          favorited: favorite_lookup["Page:#{page.id}"] == true,
          workspace_name: page.workspace.name,
          path: page_path(workspace_slug: page.workspace.slug, id: page.id)
        }
      end
  end

  def database_rows(workspace_ids, owner_email_lookup, favorite_lookup)
    policy_scope(Database)
      .where(workspace_id: workspace_ids)
      .active
      .includes(:workspace, :created_by)
      .to_a
      .map do |database|
        creator_email = owner_email_lookup[database.workspace_id] || "—"
        {
          kind: "database",
          title: database.name,
          icon: database.icon.presence || "🗃️",
          created_by: database.created_by&.email || creator_email,
          created_time: database.created_at,
          last_edited_by: database.created_by&.email || creator_email,
          last_edited_time: database.updated_at,
          last_visited_time: nil,
          visibility: database.permission_mode == "private_database" ? "private" : "shared",
          favorited: favorite_lookup["Database:#{database.id}"] == true,
          workspace_name: database.workspace.name,
          path: database_path(workspace_slug: database.workspace.slug, id: database.id)
        }
      end
  end

  def apply_filters!
    apply_tab_filter!
    apply_source_filter!
    apply_visibility_filter!
    apply_property_filter!
    apply_search_filter!
    apply_favorites_only_filter!
  end

  def apply_tab_filter!
    case @tab
    when "recents"
      recent_cutoff = 1.week.ago
      @library_rows.select! { |row| row[:last_edited_time].present? && row[:last_edited_time] >= recent_cutoff }
    when "favorites"
      @library_rows.select! { |row| row[:favorited] }
    when "shared"
      @library_rows.select! { |row| row[:visibility] == "shared" }
    when "private"
      @library_rows.select! { |row| row[:visibility] == "private" }
    end
  end

  def apply_source_filter!
    return if @source_filter == "all"

    @library_rows.select! { |row| row[:kind] == @source_filter }
  end

  def apply_visibility_filter!
    return if @visibility_filter == "all"

    @library_rows.select! { |row| row[:visibility] == @visibility_filter }
  end

  def apply_property_filter!
    return if @property_filter.blank? || @property_filter_value.blank?

    normalized = @property_filter_value.downcase
    @library_rows.select! do |row|
      value = property_value_for(row, @property_filter)
      value.to_s.downcase.include?(normalized)
    end
  end

  def apply_search_filter!
    return if @search_query.blank?

    query = @search_query.downcase
    @library_rows.select! do |row|
      haystack = [
        row[:title],
        row[:created_by],
        row[:last_edited_by],
        row[:workspace_name],
        row[:kind],
        row[:visibility]
      ].join(" ").downcase
      haystack.include?(query)
    end
  end

  def apply_favorites_only_filter!
    return unless @favorites_only

    @library_rows.select! { |row| row[:favorited] }
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

  def apply_pagination!
    @per_page = LIBRARY_PAGE_SIZE
    @current_page = resolved_page
    @total_rows = @library_rows.length
    @total_pages = [ (@total_rows.to_f / @per_page).ceil, 1 ].max
    @current_page = @total_pages if @current_page > @total_pages

    start_index = (@current_page - 1) * @per_page
    @library_rows = @library_rows.slice(start_index, @per_page) || []
    @page_start = @total_rows.zero? ? 0 : start_index + 1
    @page_end = @total_rows.zero? ? 0 : start_index + @library_rows.length
  end

  def resolved_page
    requested = params[:page].to_i
    requested.positive? ? requested : 1
  end

  def property_value_for(row, property_key)
    case property_key
    when "page_name"
      row[:title]
    when "created_by"
      row[:created_by]
    when "workspace"
      row[:workspace_name]
    when "source"
      row[:kind]
    when "created_time"
      timestamp_value(row[:created_time])
    when "last_edited_by"
      row[:last_edited_by]
    when "last_edited_time"
      timestamp_value(row[:last_edited_time])
    when "last_visited_time"
      timestamp_value(row[:last_visited_time])
    else
      ""
    end
  end

  def timestamp_value(value)
    value&.strftime("%Y-%m-%d %H:%M").to_s
  end
end
