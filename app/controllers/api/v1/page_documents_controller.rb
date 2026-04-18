module Api
  module V1
    class PageDocumentsController < BaseController
      require_api_token_scopes(
        show: ApiToken::SCOPE_PAGE_DOCUMENTS_READ,
        create: ApiToken::SCOPE_PAGE_DOCUMENTS_WRITE,
        append: ApiToken::SCOPE_PAGE_DOCUMENTS_WRITE
      )

      before_action :set_workspace!
      before_action :set_page!, only: %i[show append]

      def show
        authorize @page, :show?

        result = ::Pages::MarkdownExportService.call(page: @page)

        render json: {
          data: {
            page: Api::V1::Serializers::PageSerializer.render(@page),
            markdown: result.markdown,
            attachments: serialize_attachments(result.attachments)
          }
        }, status: :ok
      end

      def create
        page = workspace.pages.new(page_attributes)
        page.created_by = current_user
        authorize page, :create?

        imported_blocks = nil
        skipped_documents = []

        ActiveRecord::Base.transaction do
          page.save!
          result = ::Pages::ImportMarkdownService.call(
            page: page,
            workspace: workspace,
            user: current_user,
            markdown: markdown_document_params.fetch(:markdown),
            filename: markdown_document_params[:filename]
          )
          imported_blocks = result.imported_blocks
          skipped_documents = result.skipped_documents
        end

        render json: {
          data: {
            page: Api::V1::Serializers::PageSerializer.render(page),
            imported_blocks: Api::V1::Serializers::BlockSerializer.render_collection(imported_blocks),
            skipped_documents: skipped_documents
          }
        }, status: :created
      rescue ActiveRecord::RecordInvalid => error
        render_validation_errors(error.record)
      rescue ::Pages::ImportMarkdownService::Error => error
        render_error(code: "validation_failed", message: error.message, status: :unprocessable_entity)
      end

      def append
        authorize @page, :update?

        result = ::Pages::ImportMarkdownService.call(
          page: @page,
          workspace: workspace,
          user: current_user,
          markdown: append_markdown_params.fetch(:markdown),
          insert_after_id: append_markdown_params[:insert_after_block_id],
          filename: append_markdown_params[:filename]
        )

        render json: {
          data: {
            page: Api::V1::Serializers::PageSerializer.render(@page.reload),
            imported_blocks: Api::V1::Serializers::BlockSerializer.render_collection(result.imported_blocks),
            skipped_documents: result.skipped_documents
          }
        }, status: :ok
      rescue ::Pages::ImportMarkdownService::Error => error
        render_error(code: "validation_failed", message: error.message, status: :unprocessable_entity)
      end

      private

      def set_page!
        @page = policy_scope(Page).for_workspace(workspace).find(params[:id])
      end

      def page_attributes
        markdown_document_params.slice(:title, :parent_page_id, :permission_mode)
      end

      def markdown_document_params
        params.require(:page_document).permit(:title, :parent_page_id, :permission_mode, :filename, :markdown)
      end

      def append_markdown_params
        params.require(:page_document).permit(:filename, :markdown, :insert_after_block_id)
      end

      def serialize_attachments(attachments)
        Array(attachments).map do |attachment|
          {
            block_id: attachment.block_id,
            filename: attachment.filename,
            relative_path: attachment.relative_path,
            byte_size: attachment.blob.byte_size,
            content_type: attachment.blob.content_type
          }
        end
      end
    end
  end
end
