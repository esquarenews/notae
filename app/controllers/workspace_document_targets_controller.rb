class WorkspaceDocumentTargetsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  DEFAULT_LIMIT = 12
  MAX_LIMIT = 20

  def index
    authorize @workspace, :show?

    render json: {
      data: {
        results: document_targets
      }
    }
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def document_targets
    case params[:kind].to_s
    when "move_page"
      page_results(move_scope)
    when "note"
      page_results(note_scope)
    when "page"
      page_results(page_scope)
    when "grid"
      database_results(database_scope)
    else
      []
    end
  end

  def page_scope
    scope = policy_scope(Page).for_workspace(@workspace).active.select(:id, :title, :updated_at)
    if params[:exclude_page_id].present?
      scope = scope.where.not(id: params[:exclude_page_id])
    end

    apply_text_search(scope, target: :page)
  end

  def move_scope
    page_scope
  end

  def note_scope
    page_scope.left_outer_joins(:linked_database).where(databases: { id: nil })
  end

  def database_scope
    scope = policy_scope(Database).for_workspace(@workspace).active.select(:id, :name, :updated_at)
    apply_text_search(scope, target: :database)
  end

  def page_results(scope)
    apply_ordering(scope, column: "pages.title").limit(result_limit).map do |page|
      {
        id: page.id,
        label: page.title.presence || "Untitled nota",
        meta: page.updated_at&.strftime("%b %-d")
      }
    end
  end

  def database_results(scope)
    apply_ordering(scope, column: "databases.name").limit(result_limit).map do |database|
      {
        id: database.id,
        label: database.name.presence || "Untitled grid",
        meta: database.updated_at&.strftime("%b %-d")
      }
    end
  end

  def apply_text_search(scope, target:)
    return scope if search_query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(search_query.downcase)}%"
    case target
    when :page
      scope.where("LOWER(pages.title) LIKE ?", pattern)
    when :database
      scope.where("LOWER(databases.name) LIKE ?", pattern)
    else
      scope
    end
  end

  def apply_ordering(scope, column:)
    scope.order(updated_at: :desc, id: :asc)
  end

  def search_query
    @search_query ||= params[:q].to_s.strip
  end

  def result_limit
    requested_limit = params[:limit].to_i
    return DEFAULT_LIMIT if requested_limit <= 0

    [ requested_limit, MAX_LIMIT ].min
  end
end
