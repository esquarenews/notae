class PageExportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_page, only: %i[markdown pdf create]
  before_action :set_page_export, only: :download

  def markdown
    authorize @page, :show?

    result = Pages::MarkdownExportService.call(page: @page)
    send_data result.markdown,
              filename: "#{sanitize_filename(@page.title)}.md",
              type: "text/markdown; charset=utf-8",
              disposition: "attachment"
  end

  def pdf
    authorize @page, :show?

    result = Pages::PdfExportService.call(page: @page)
    send_data result.pdf,
              filename: "#{sanitize_filename(@page.title)}.pdf",
              type: "application/pdf",
              disposition: "attachment"
  end

  def create
    @page_export = PageExport.new(page: @page, workspace: @workspace, requested_by: current_user)
    authorize @page_export

    if @page_export.save
      begin
        PageExports::BuildZipJob.perform_later(@page_export.id)
        redirect_to page_redirect_path, notice: "Export queued."
      rescue StandardError => error
        @page_export.mark_failed!("Queue unavailable: #{error.class}: #{error.message}")
        redirect_to page_redirect_path, alert: "Export queue unavailable. Start Redis/Sidekiq and retry."
      end
    else
      redirect_to page_redirect_path, alert: @page_export.errors.full_messages.to_sentence
    end
  end

  def download
    authorize @page_export, :download?
    raise ActiveRecord::RecordNotFound unless @page_export.downloadable?

    send_data @page_export.archive_file.download,
              filename: @page_export.archive_file.filename.to_s,
              type: "application/zip",
              disposition: "attachment"
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_page
    @page = policy_scope(Page).for_workspace(@workspace).find(params[:id])
  end

  def set_page_export
    @page_export = policy_scope(PageExport).for_workspace(@workspace).find_by!(token: params[:token])
  end

  def sanitize_filename(value)
    value.to_s.parameterize.presence || "page-export"
  end

  def page_redirect_path
    route_params = { workspace_slug: @workspace.slug, id: @page.id }
    route_params[:options_menu] = "open" if params[:options_menu].to_s == "open"
    page_path(route_params)
  end
end
