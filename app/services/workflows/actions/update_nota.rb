module Workflows
  module Actions
    class UpdateNota
      BODY_MODES = %w[keep replace append].freeze

      def initialize(workflow_run:)
        @workflow_run = workflow_run
      end

      def call
        page = Pundit.policy_scope!(workflow_run.user, Page)
                     .for_workspace(workflow_run.workspace)
                     .active
                     .find(workflow_run.input_json["page_id"])
        title = workflow_run.input_json["title"].to_s.strip
        markdown = requested_markdown
        mode = body_mode
        raise ArgumentError, "Unsupported Nota body mode: #{mode}" unless BODY_MODES.include?(mode)

        if title.present?
          page.title = title
          Pundit.authorize(workflow_run.user, page, :update?)
          page.save!
        end

        import_markdown!(page, markdown: markdown) if markdown.present? && mode != "keep"
        result_for(page.id)
      end

      private

      attr_reader :workflow_run

      def import_markdown!(page, markdown:)
        Pundit.authorize(workflow_run.user, page, :update?)
        page.blocks.active.destroy_all unless append_markdown?
        Pages::ImportMarkdownService.call(
          page: page,
          workspace: workflow_run.workspace,
          user: workflow_run.user,
          markdown: markdown,
          filename: workflow_run.input_json["filename"]
        )
      end

      def append_markdown?
        body_mode == "append"
      end

      def requested_markdown
        workflow_run.input_json["markdown"].presence || workflow_run.input_json["body"].to_s
      end

      def body_mode
        @body_mode ||= (
          workflow_run.input_json["body_mode"].presence ||
          workflow_run.input_json["content_mode"].presence ||
          "replace"
        ).to_s
      end

      def result_for(page_id)
        page = Pundit.policy_scope!(workflow_run.user, Page)
                     .for_workspace(workflow_run.workspace)
                     .includes(:blocks)
                     .find(page_id)
        export = Pages::MarkdownExportService.call(page: page)

        {
          "target_type" => "Page",
          "target_id" => page.id,
          "title" => page.title,
          "url" => Rails.application.routes.url_helpers.page_path(workspace_slug: workflow_run.workspace.slug, id: page.id),
          "page" => Api::V1::Serializers::PageSerializer.render(page),
          "markdown" => export.markdown
        }
      end
    end
  end
end
