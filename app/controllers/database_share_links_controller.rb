class DatabaseShareLinksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_database
  before_action :set_database_share_link, only: :destroy

  def create
    @database_share_link = @database.database_share_links.new(database_share_link_params)
    @database_share_link.created_by = current_user
    authorize @database_share_link

    if @database_share_link.save
      log_public_share_event!(
        kind: "public_grid_share_link_created",
        share_link_id: @database_share_link.id,
        expires_at: @database_share_link.expires_at
      )
      redirect_to database_redirect_path, notice: "Public grid share link created."
    else
      redirect_to database_redirect_path, alert: @database_share_link.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @database_share_link
    @database_share_link.revoke!
    log_public_share_event!(
      kind: "public_grid_share_link_revoked",
      share_link_id: @database_share_link.id
    )
    redirect_to database_redirect_path, notice: "Public grid share link revoked."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_database
    @database = policy_scope(Database).for_workspace(@workspace).find(params[:database_id])
  end

  def set_database_share_link
    @database_share_link = policy_scope(DatabaseShareLink).for_database(@database).find(params[:id])
  end

  def database_share_link_params
    params.fetch(:database_share_link, {}).permit(:expires_at)
  end

  def log_public_share_event!(kind:, share_link_id:, expires_at: nil)
    AuditEvent.create!(
      workspace: @workspace,
      actor: current_user,
      action: "share",
      metadata: {
        kind: kind,
        database_id: @database.id,
        share_link_id: share_link_id,
        expires_at: expires_at
      },
      auditable: @database
    )
  end

  def database_redirect_path
    route_params = {
      workspace_slug: @workspace.slug,
      id: @database.id
    }
    route_params[:view_id] = params[:view_id] if params[:view_id].present?
    route_params[:month] = params[:month] if params[:month].present?
    route_params[:sort_property_id] = params[:sort_property_id] if params[:sort_property_id].present?
    route_params[:sort_direction] = params[:sort_direction] if params[:sort_direction].present?
    route_params[:sort_mode] = params[:sort_mode] if params[:sort_mode].present?
    route_params[:filter_property_id] = params[:filter_property_id] if params[:filter_property_id].present?
    route_params[:filter_value] = params[:filter_value] if params[:filter_value].present?
    route_params[:filter_operator] = params[:filter_operator] if params[:filter_operator].present?
    route_params[:rows_page] = params[:rows_page] if params[:rows_page].present?
    route_params[:split_panel] = params[:split_panel] if params[:split_panel].present?
    route_params[:split_page_id] = params[:split_page_id] if params[:split_page_id].present?
    route_params[:split_source] = params[:split_source] if params[:split_source].present?
    route_params[:split_row_id] = params[:split_row_id] if params[:split_row_id].present?
    route_params[:task_row_id] = params[:task_row_id] if params[:task_row_id].present?
    route_params[:options_menu] = "open"
    database_path(route_params)
  end
end
