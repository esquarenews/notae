module Api
  module V1
    class WorkspacesController < BaseController
      require_api_token_scopes index: ApiToken::SCOPE_WORKSPACES_READ

      DEFAULT_LIMIT = 25
      MAX_LIMIT = 100

      def index
        authorize Workspace, :index?

        workspaces = policy_scope(Workspace).order(updated_at: :desc, id: :asc)
        workspaces = apply_name_filter(workspaces)
        workspaces = workspaces.limit(result_limit)

        render json: {
          data: Api::V1::Serializers::WorkspaceSerializer.render_collection(workspaces, user: current_user)
        }, status: :ok
      end

      private

      def apply_name_filter(scope)
        return scope if search_query.blank?

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(search_query.downcase)}%"
        scope.where("LOWER(workspaces.name) LIKE ? OR LOWER(workspaces.slug) LIKE ?", pattern, pattern)
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
  end
end
