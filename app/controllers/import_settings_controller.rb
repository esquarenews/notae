class ImportSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?
  end

  def create
    authorize @workspace, :show?

    files = normalized_import_files
    if files.empty?
      redirect_to workspace_import_settings_path(workspace_slug: @workspace.slug), alert: "Select at least one file to import."
      return
    end

    if files_require_page_import_authorization?(files)
      page_probe = Page.new(workspace: @workspace, created_by: current_user, title: "Import")
      authorize page_probe, :create?
    end

    if files_require_grid_import_authorization?(files)
      database_probe = Database.new(workspace: @workspace, created_by: current_user, name: "Import")
      authorize database_probe, :create?
    end

    result = Imports::IngestService.call(workspace: @workspace, user: current_user, files: files)
    if result.imported_count.positive?
      notice_parts = [ import_notice_for(result) ]
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

  def normalized_import_files
    Array(import_params[:files]).select { |file| uploaded_file_present?(file) }
  end

  def uploaded_file_present?(file)
    file.respond_to?(:original_filename) && file.original_filename.to_s.strip.present?
  end

  def files_require_grid_import_authorization?(files)
    Array(files).any? do |file|
      extension = File.extname(file.respond_to?(:original_filename) ? file.original_filename.to_s : file.to_s).downcase
      [ ".csv", ".zip" ].include?(extension)
    end
  end

  def files_require_page_import_authorization?(files)
    Array(files).any? do |file|
      extension = File.extname(file.respond_to?(:original_filename) ? file.original_filename.to_s : file.to_s).downcase
      extension != ".csv"
    end
  end

  def import_notice_for(result)
    parts = []
    if result.imported_page_count.positive?
      label = result.imported_page_count == 1 ? "Nota" : "Notarum"
      parts << "#{result.imported_page_count} #{label}"
    end
    if result.imported_database_count.positive?
      label = result.imported_database_count == 1 ? "Grid" : "Grids"
      parts << "#{result.imported_database_count} #{label}"
    end

    "Imported #{parts.to_sentence}."
  end
end
