module Workflows
  module Actions
    class CreateNota
      def initialize(workflow_run:)
        @workflow_run = workflow_run
      end

      def call
        title = workflow_run.input_json["title"].to_s.strip
        markdown = workflow_run.input_json["markdown"].presence || workflow_run.input_json["body"].to_s
        raise ArgumentError, "Nota title is required" if title.blank?
        raise ArgumentError, "Nota body is required" if markdown.strip.blank?

        page = workflow_run.workspace.pages.new(
          title: title,
          created_by: workflow_run.user,
          page_kind: "nota"
        )
        Pundit.authorize(workflow_run.user, page, :create?)
        page.save!

        Pundit.authorize(workflow_run.user, page, :update?)
        Pages::ImportMarkdownService.call(
          page: page,
          workspace: workflow_run.workspace,
          user: workflow_run.user,
          markdown: markdown,
          filename: workflow_run.input_json["filename"]
        )

        result_for(page.id)
      end

      private

      attr_reader :workflow_run

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
