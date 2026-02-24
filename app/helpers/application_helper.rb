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

  def notae_sidebar_link_classes(path = nil, active: false)
    is_active = active || (path.present? && current_page?(path))
    base = "notae-sidebar-link"
    is_active ? "#{base} active" : base
  end
end
