module Search
  class WorkspaceSearchService
    Result = Struct.new(:kind, :title, :excerpt, :url, :score, keyword_init: true)

    def initialize(user:, workspace:, query:)
      @user = user
      @workspace = workspace
      @query = query.to_s.strip
    end

    def call
      return [] if query.blank?

      (page_results + block_results + db_row_results).sort_by { |result| -result.score.to_f }
    end

    private

    attr_reader :user, :workspace, :query

    def page_results
      Pundit.policy_scope!(user, Page)
            .for_workspace(workspace)
            .active
            .distinct(false)
            .search_full_text(query)
            .limit(15)
            .map do |page|
        Result.new(
          kind: "Page",
          title: page.title,
          excerpt: highlighted_excerpt(page.title),
          url: Rails.application.routes.url_helpers.page_path(workspace_slug: workspace.slug, id: page.id),
          score: 30
        )
      end
    end

    def block_results
      Pundit.policy_scope!(user, Block)
            .for_workspace(workspace)
            .active
            .search_full_text(query)
            .includes(:page)
            .limit(20)
            .map do |block|
        Result.new(
          kind: "Block",
          title: block.page.title,
          excerpt: highlighted_excerpt(block.search_text),
          url: "#{Rails.application.routes.url_helpers.page_path(workspace_slug: workspace.slug, id: block.page_id)}#block_#{block.id}",
          score: 20
        )
      end
    end

    def db_row_results
      Pundit.policy_scope!(user, DbRow)
            .for_workspace(workspace)
            .active
            .search_full_text(query)
            .includes(:database)
            .limit(15)
            .map do |row|
        Result.new(
          kind: "Row",
          title: row.title.presence || row.database.name,
          excerpt: highlighted_excerpt(row.search_text),
          url: Rails.application.routes.url_helpers.database_path(workspace_slug: workspace.slug, id: row.database_id, anchor: "row_#{row.id}"),
          score: 10
        )
      end
    end

    def highlighted_excerpt(text)
      compact = text.to_s.squish
      return "" if compact.blank?

      ActionController::Base.helpers.highlight(
        compact.truncate(220),
        query_terms,
        highlighter: "<mark>\\1</mark>"
      )
    end

    def query_terms
      @query_terms ||= query.split(/\s+/).reject(&:blank?).uniq
    end
  end
end
