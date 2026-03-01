class KalendariumConnectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_connection, only: %i[update destroy sync]

  def create
    owner = resolve_owner
    connection = KalendariumConnection.new(connection_params.merge(
      workspace: @workspace,
      owner: owner,
      created_by: current_user,
      status: "disconnected"
    ))
    authorize connection

    if connection.save
      flash_type, message = sync_connection_if_requested(connection, success_message: "Calendar connection added and synced.")
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), flash_type => message
    else
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: connection.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @connection

    if @connection.update(connection_params)
      flash_type, message = sync_connection_if_requested(@connection, success_message: "Connection updated and synced.", fallback_message: "Connection updated.")
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), flash_type => message
    else
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: @connection.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @connection
    @connection.destroy!
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Connection removed."
  end

  def sync
    authorize @connection, :sync?
    Kalendarium::SyncConnectionJob.perform_later(@connection.id)
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Sync queued."
  end

  def google_callback
    authorize @workspace, :show?
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Google callback captured. Save tokens in connection settings to complete setup."
  end

  def icloud_callback
    authorize @workspace, :show?
    redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "iCloud callback captured. Save credentials in connection settings to complete setup."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_connection
    @connection = policy_scope(KalendariumConnection).for_workspace(@workspace).find(params[:id])
  end

  def connection_params
    params.require(:kalendarium_connection).permit(
      :provider,
      :label,
      :enabled,
      :remote_account_id,
      :access_token,
      :refresh_token,
      :provider_username,
      :provider_password,
      :ics_url
    )
  end

  def resolve_owner
    owner_scope = params.dig(:kalendarium_connection, :owner_scope).to_s
    return @workspace if owner_scope == "workspace"

    current_user
  end

  def sync_connection_if_requested(connection, success_message:, fallback_message: "Calendar connection added.")
    return [ :notice, fallback_message ] unless params[:sync_now].to_s == "1"

    Kalendarium::ConnectionSyncService.new(connection: connection).call
    [ :notice, success_message ]
  rescue StandardError => error
    [ :alert, "Connection saved but sync failed: #{error.message}" ]
  end
end
