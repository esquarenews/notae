class WorkspaceExportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_workspace_export, only: :download
  before_action :load_workspace_exports, only: :create

  def create
    @workspace_export = @workspace.workspace_exports.new(requested_by: current_user)
    authorize @workspace_export

    if @workspace_export.save
      WorkspaceExports::BuildZipJob.perform_later(@workspace_export.id)
      load_workspace_exports
      render_response("notice", "Workspace backup queued. Refresh this section in a moment if the zip is not ready yet.")
    else
      render_response("alert", @workspace_export.errors.full_messages.to_sentence, status: :unprocessable_entity)
    end
  end

  def download
    authorize @workspace_export, :download?

    raise ActiveRecord::RecordNotFound unless @workspace_export.downloadable?

    send_data @workspace_export.archive_file.download,
              filename: @workspace_export.archive_file.filename.to_s,
              type: "application/zip",
              disposition: :attachment
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_workspace_export
    @workspace_export = policy_scope(WorkspaceExport).for_workspace(@workspace).find_by!(token: params[:token])
  end

  def load_workspace_exports
    @workspace_exports = policy_scope(WorkspaceExport).for_workspace(@workspace).recent_first.limit(8).to_a
  end

  def render_response(type, message, status: :ok)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          settings_flash_stream(type, message),
          turbo_stream.replace(
            "workspace_backup_exports_panel",
            partial: "general_settings/workspace_exports",
            locals: {
              workspace: @workspace,
              workspace_exports: @workspace_exports,
              can_export: policy(WorkspaceExport.new(workspace: @workspace, requested_by: current_user)).create?
            }
          )
        ], status: status
      end
      format.html do
        redirect_to workspace_general_settings_path(workspace_slug: @workspace.slug, settings_workspace_slug: @workspace.slug),
                    type => message
      end
    end
  end
end
