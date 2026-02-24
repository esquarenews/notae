require "stringio"
require "zip"

module PageExports
  class BuildZipJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    def perform(page_export_id)
      page_export = PageExport.find(page_export_id)
      return if page_export.expired?
      return if page_export.ready?

      result = Pages::MarkdownExportService.call(page: page_export.page)
      archive_data = build_archive(page: page_export.page, result: result)

      page_export.archive_file.attach(
        io: StringIO.new(archive_data),
        filename: archive_filename(page_export.page),
        content_type: "application/zip"
      )
      page_export.mark_ready!
    rescue StandardError => error
      page_export&.mark_failed!(error.message)
    end

    private

    def build_archive(page:, result:)
      Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry(markdown_filename(page))
        zip.write(result.markdown)

        result.attachments.each do |attachment|
          zip.put_next_entry(attachment.relative_path)
          zip.write(attachment.blob.download)
        end
      end.string
    end

    def markdown_filename(page)
      "#{base_filename(page)}.md"
    end

    def archive_filename(page)
      "#{base_filename(page)}-export.zip"
    end

    def base_filename(page)
      page.title.to_s.parameterize.presence || "page"
    end
  end
end
