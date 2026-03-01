class KalendariumConnectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_connection, only: %i[update destroy sync]

  def create
    owner = resolve_owner
    connection = KalendariumConnection.new(connection_params.merge(
      workspace: @workspace,
      owner: owner,
      created_by: current_user
    ))
    authorize connection

    if connection.save
      Kalendarium::SyncConnectionJob.perform_later(connection.id) if params[:sync_now].to_s == "1"
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Calendar connection added."
    else
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: connection.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @connection

    if @connection.update(connection_params)
      Kalendarium::SyncConnectionJob.perform_later(@connection.id) if params[:sync_now].to_s == "1"
      redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Connection updated."
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
      :status,
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
end
