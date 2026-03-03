module ApplicationHelper
  def ui_workspaces
    return [] unless user_signed_in?

    @ui_workspaces ||= workspace_scope_with_slug.order(:created_at).to_a
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
                              .active
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
      .active
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
      .meeting_notes
      .order(updated_at: :desc)
      .limit(limit)
      .to_a
  end

  def ui_sidebar_recent_workspaces(limit: 6)
    return [] unless user_signed_in?

    workspace_scope_with_slug
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
        next if record.respond_to?(:archived?) && record.archived?

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

  def notae_icon_svg(name, css_class: nil)
    svg_class = [ "notae-icon-svg", css_class ].compact.join(" ")
    markup =
      case name.to_sym
      when :nota
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M4 1.5h5L12.5 5v9.5H4V1.5Z" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/><path d="M9 1.5V5h3.5" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/><path d="M5.7 8h5M5.7 10.5h5" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>'
      when :meeting
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="6" y="2.3" width="4" height="7.2" rx="2" stroke="currentColor" stroke-width="1.4"/><path d="M4 7.6a4 4 0 0 0 8 0M8 11.6v2.1M5.8 13.7h4.4" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>'
      when :grid
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="2.2" y="2.2" width="11.6" height="11.6" rx="2" stroke="currentColor" stroke-width="1.3"/><path d="M2.8 6h10.4M2.8 9.3h10.4M6 2.8v10.4" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>'
      when :workspace
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M2.2 5.2 8 2.2l5.8 3v6.6L8 14.8l-5.8-3Z" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/><path d="M8 2.2v12.6M2.2 5.2 8 8.1l5.8-2.9" stroke="currentColor" stroke-width="1.1" stroke-linejoin="round"/></svg>'
      when :home
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="m2.3 7.2 5.7-4.6 5.7 4.6" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/><path d="M4.2 6.4v7h7.6v-7" stroke="currentColor" stroke-width="1.3" stroke-linejoin="round"/></svg>'
      when :search
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="7" cy="7" r="4.2" stroke="currentColor" stroke-width="1.3"/><path d="m10.2 10.2 3 3" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/></svg>'
      when :notifications
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M8 2.2a3.2 3.2 0 0 0-3.2 3.2v2l-1.3 2.1h9L11.2 7.4v-2A3.2 3.2 0 0 0 8 2.2Z" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/><path d="M6.6 11.6a1.4 1.4 0 0 0 2.8 0" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>'
      when :library
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="2.3" y="2.6" width="3" height="10.8" rx="1" stroke="currentColor" stroke-width="1.2"/><rect x="6.6" y="2.6" width="3" height="10.8" rx="1" stroke="currentColor" stroke-width="1.2"/><rect x="10.9" y="2.6" width="2.8" height="10.8" rx="1" stroke="currentColor" stroke-width="1.2"/></svg>'
      when :kalendarium
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><rect x="2.2" y="3.2" width="11.6" height="10.6" rx="2" stroke="currentColor" stroke-width="1.2"/><path d="M5 1.8v2.7M11 1.8v2.7M2.2 6h11.6" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>'
      when :ai_history
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3 3.2h10v7.3H7.3L4 13V10.5H3V3.2Z" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/><path d="M5.4 6.2h5.2M5.4 8.1h3.7" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/></svg>'
      when :settings
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="8" cy="8" r="2.2" stroke="currentColor" stroke-width="1.2"/><path d="M8 1.9v1.4M8 12.7v1.4M13.1 8h1.4M1.5 8h1.4M11.9 4.1l1 1M3.1 11.9l1-1M11.9 11.9l1-1M3.1 4.1l1 1" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/></svg>'
      when :trash
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M2.8 4.4h10.4M6.1 2.6h3.8M4.2 4.4l.7 8.2h6.2l.7-8.2" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/><path d="M6.8 6.4v4.2M9.2 6.4v4.2" stroke="currentColor" stroke-width="1.1" stroke-linecap="round"/></svg>'
      when :sign_out
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M6.2 2.4H3.6a1.2 1.2 0 0 0-1.2 1.2v8.8a1.2 1.2 0 0 0 1.2 1.2h2.6" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/><path d="M9.1 5.1 12 8l-2.9 2.9M5.2 8H12" stroke="currentColor" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
      else
        '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><circle cx="8" cy="8" r="4.2" stroke="currentColor" stroke-width="1.2"/></svg>'
      end

    content_tag(:span, raw(markup), class: svg_class, aria: { hidden: true })
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

  private

  def workspace_scope_with_slug
    policy_scope(Workspace).where.not(slug: [ nil, "" ])
  end
end
