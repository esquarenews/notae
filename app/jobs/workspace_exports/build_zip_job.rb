require "stringio"

module WorkspaceExports
  class BuildZipJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    def perform(workspace_export_id)
      workspace_export = WorkspaceExport.find(workspace_export_id)
      return if workspace_export.expired?
      return if workspace_export.ready?

      archive_data = WorkspaceExports::ArchiveBuilder.call(workspace_export:)
      workspace_export.archive_file.attach(
        io: StringIO.new(archive_data),
        filename: archive_filename(workspace_export),
        content_type: "application/zip"
      )
      workspace_export.mark_ready!
    rescue StandardError => error
      workspace_export&.mark_failed!(error.message)
    end

    private

    def archive_filename(workspace_export)
      timestamp = (workspace_export.created_at || Time.current).utc.strftime("%Y%m%d-%H%M%S")
      "#{workspace_export.workspace.slug}-backup-#{timestamp}.zip"
    end
  end
end
