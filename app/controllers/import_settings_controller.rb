class ImportSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?
  end

  def create
    page_probe = Page.new(workspace: @workspace, created_by: current_user, title: "Import")
    authorize page_probe, :create?

    files = import_params[:files].to_a.reject(&:blank?)
    if files.empty?
      redirect_to workspace_import_settings_path(workspace_slug: @workspace.slug), alert: "Select at least one file to import."
      return
    end

    result = Imports::IngestService.call(workspace: @workspace, user: current_user, files: files)
    if result.imported_count.positive?
      imported_label = result.imported_count == 1 ? "Nota" : "Notarum"
      notice_parts = [ "Imported #{result.imported_count} #{imported_label}." ]
      notice_parts << "Skipped #{result.skipped_files.count} unsupported file#{'s' if result.skipped_files.count != 1}." if result.skipped_files.any?
      redirect_to workspace_import_settings_path(workspace_slug: @workspace.slug), notice: notice_parts.join(" ")
    else
      errors = []
      errors << "No supported files were imported." if result.skipped_files.any?
      errors << result.errors.join(" ") if result.errors.any?
      redirect_to workspace_import_settings_path(workspace_slug: @workspace.slug), alert: errors.compact.join(" ").presence || "Import failed."
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def import_params
    params.fetch(:import, {}).permit(files: [])
  end
end
