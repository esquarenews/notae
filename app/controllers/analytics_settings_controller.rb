class AnalyticsSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user
  before_action :authorize_analytics!
  before_action :build_snapshot

  def show; end

  def export_pdf
    TenantLimits::Enforcer.enforce!(workspace: @workspace, feature: :exports)
    result = Analytics::PdfExportService.call(snapshot: @snapshot)

    send_data result.pdf,
              filename: analytics_filename("pdf"),
              type: "application/pdf",
              disposition: "attachment"
  end

  def create_nota
    page = @workspace.pages.new(
      title: "#{@analytics_scope == "all" ? "App-wide activity" : "My activity"} - #{@date_range.label}",
      created_by: current_user,
      permission_mode: :private_page
    )
    authorize page, :create?

    ActiveRecord::Base.transaction do
      page.save!
      Pages::ImportMarkdownService.call(
        page: page,
        workspace: @workspace,
        user: current_user,
        markdown: Analytics::ReportMarkdownBuilder.call(snapshot: @snapshot),
        filename: "notae-analytics.md"
      )
    end

    redirect_to page_path(workspace_slug: @workspace.slug, id: page.id), notice: "Analytics snapshot added to a private Nota."
  rescue ActiveRecord::RecordInvalid, Pages::ImportMarkdownService::Error => error
    redirect_to analytics_settings_path, alert: error.message
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_user
    @user = policy_scope(User).find(current_user.id)
  end

  def authorize_analytics!
    authorize @workspace, :show?
    authorize @user, :show?
  end

  def build_snapshot
    @analytics_scope = params[:scope].to_s == "all" ? "all" : "workspace"
    @available_workspaces = available_analytics_workspaces
    selected_workspaces = @analytics_scope == "all" ? @available_workspaces : [ @workspace ]
    @date_range = Analytics::DateRange.new(params: filter_params.to_h.symbolize_keys)
    @snapshot = Analytics::SnapshotBuilder.call(
      user: @user,
      workspaces: selected_workspaces,
      scope: @analytics_scope,
      date_range: @date_range
    )
  end

  def available_analytics_workspaces
    current_user.memberships.load
    policy_scope(Workspace)
      .where.not(slug: [ nil, "" ])
      .includes(:workspace_subscription)
      .order(:name)
      .select { |candidate_workspace| policy(candidate_workspace).show? }
  end

  def filter_params
    params.permit(:period, :start_date, :end_date)
  end

  def analytics_settings_path
    workspace_analytics_settings_path(
      workspace_slug: @workspace.slug,
      scope: @analytics_scope,
      **@date_range.to_params
    )
  end

  def analytics_filename(extension)
    scope_slug = @analytics_scope == "all" ? "all-workspaces" : @workspace.slug
    "notae-analytics-#{scope_slug}-#{@date_range.start_date}-to-#{@date_range.end_date}.#{extension}"
  end
end
