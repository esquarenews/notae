module Workflows
  module Actions
    class CreateNota
      def initialize(workflow_run:)
        @workflow_run = workflow_run
      end

      def call
        title = workflow_run.input_json["title"].to_s.strip
        body = workflow_run.input_json["body"].to_s
        raise ArgumentError, "Nota title is required" if title.blank?
        raise ArgumentError, "Nota body is required" if body.strip.blank?

        page = workflow_run.workspace.pages.create!(
          title: title,
          created_by: workflow_run.user,
          page_kind: "nota"
        )
        page.blocks.create!(
          workspace: workflow_run.workspace,
          created_by: workflow_run.user,
          block_type: "paragraph",
          position: Block::POSITION_GAP,
          content_json: {
            "type" => "doc",
            "content" => [
              {
                "type" => "paragraph",
                "content" => [ { "type" => "text", "text" => body } ]
              }
            ]
          }
        )

        {
          "target_type" => "Page",
          "target_id" => page.id,
          "title" => page.title,
          "url" => Rails.application.routes.url_helpers.page_path(workspace_slug: workflow_run.workspace.slug, id: page.id)
        }
      end

      private

      attr_reader :workflow_run
    end
  end
end
