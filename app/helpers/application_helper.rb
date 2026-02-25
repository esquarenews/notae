module ApplicationHelper
  def ui_workspaces
    return [] unless user_signed_in?

    @ui_workspaces ||= policy_scope(Workspace).order(:created_at).to_a
  end

  def ui_current_workspace
    return nil unless user_signed_in?
    return @ui_current_workspace if defined?(@ui_current_workspace)

    requested_slug = params[:workspace_slug].presence
    @ui_current_workspace =
      if requested_slug
        ui_workspaces.find { |workspace| workspace.slug == requested_slug }
      else
        ui_workspaces.first
      end
  end

  def ui_sidebar_pages_by_parent
    workspace = ui_current_workspace
    return {} unless workspace

    @ui_sidebar_pages_by_parent ||= policy_scope(Page)
                                    .for_workspace(workspace)
                                    .active
                                    .order(:created_at)
                                    .to_a
                                    .group_by(&:parent_page_id)
  end

  def ui_sidebar_databases
    workspace = ui_current_workspace
    return [] unless workspace

    @ui_sidebar_databases ||= policy_scope(Database)
                              .for_workspace(workspace)
                              .order(:created_at)
                              .limit(12)
                              .to_a
  end

  def ui_sidebar_recent_pages(limit: 6)
    workspace = ui_current_workspace
    return [] unless workspace

    policy_scope(Page)
      .for_workspace(workspace)
      .active
      .order(updated_at: :desc)
      .limit(limit)
      .to_a
  end

  def ui_sidebar_recent_databases(limit: 6)
    workspace = ui_current_workspace
    return [] unless workspace

    policy_scope(Database)
      .for_workspace(workspace)
      .order(updated_at: :desc)
      .limit(limit)
      .to_a
  end

  def ui_sidebar_recent_meetings(limit: 6)
    workspace = ui_current_workspace
    return [] unless workspace

    policy_scope(Page)
      .for_workspace(workspace)
      .active
      .where("pages.title ILIKE ?", "%meeting%")
      .order(updated_at: :desc)
      .limit(limit)
      .to_a
  end

  def ui_sidebar_recent_workspaces(limit: 6)
    return [] unless user_signed_in?

    policy_scope(Workspace)
      .order(updated_at: :desc)
      .limit(limit)
      .to_a
  end

  def ui_sidebar_recent_favorites(limit: 6)
    workspace = ui_current_workspace
    return [] unless workspace

    policy_scope(Favorite)
      .for_workspace(workspace)
      .for_user(current_user)
      .recent
      .includes(:favoritable)
      .limit(limit * 2)
      .filter_map do |favorite|
        record = favorite.favoritable
        next if record.blank?

        type =
          case favorite.favoritable_type
          when "Page"
            :page
          when "Database"
            :database
          end
        next if type.blank?

        { type: type, record: record, updated_at: favorite.created_at }
      end
      .first(limit)
  end

  def notae_sidebar_link_classes(path = nil, active: false)
    is_active = active || (path.present? && current_page?(path))
    base = "notae-sidebar-link"
    is_active ? "#{base} active" : base
  end

  def page_cover_asset_path(cover_preset_key)
    return nil if cover_preset_key.blank?
    return nil unless Page::COVER_PRESET_KEYS.include?(cover_preset_key.to_s)

    "page_covers/#{cover_preset_key}.svg"
  end

  def notae_theme_body_class
    return "notae-theme-light" unless user_signed_in?

    case current_user.theme_preference
    when "dark"
      "notae-theme-dark"
    when "system"
      "notae-theme-system"
    else
      "notae-theme-light"
    end
  end

  def format_date_mention(date:, preference:)
    DateMentions::Formatter.format(date: date, preference: preference)
  end
end
