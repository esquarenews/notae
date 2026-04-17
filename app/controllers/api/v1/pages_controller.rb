module Api
  module V1
    class PagesController < BaseController
      before_action :set_workspace!
      DEFAULT_LIMIT = 25
      MAX_LIMIT = 100

      before_action :set_page!, only: %i[show update]

      def index
        pages = policy_scope(Page).for_workspace(workspace).active
        pages = apply_title_filter(pages)
        pages = apply_page_kind_filter(pages)
        pages = pages.order(updated_at: :desc, id: :asc).limit(result_limit)

        render json: { data: Api::V1::Serializers::PageSerializer.render_collection(pages) }, status: :ok
      end

      def show
        authorize @page, :show?

        render json: { data: Api::V1::Serializers::PageSerializer.render(@page) }, status: :ok
      end

      def create
        page = workspace.pages.new(page_params)
        page.created_by = current_user
        authorize page, :create?

        page = Api::V1::Pages::CreateService.call(workspace: workspace, actor: current_user, attributes: page_params.to_h)
        return render_validation_errors(page) unless page.persisted?

        render json: { data: Api::V1::Serializers::PageSerializer.render(page) }, status: :created
      end

      def update
        authorize @page, :update?

        page = Api::V1::Pages::UpdateService.call(page: @page, attributes: page_params.to_h)
        return render_validation_errors(page) if page.errors.any?

        render json: { data: Api::V1::Serializers::PageSerializer.render(page) }, status: :ok
      end

      private

      def set_page!
        @page = policy_scope(Page).for_workspace(workspace).find(params[:id])
      end

      def page_params
        params.require(:page).permit(:title, :parent_page_id, :permission_mode)
      end

      def apply_title_filter(scope)
        return scope if search_query.blank?

        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(search_query.downcase)}%"
        scope.where("LOWER(pages.title) LIKE ?", pattern)
      end

      def apply_page_kind_filter(scope)
        page_kind = params[:page_kind].to_s.strip
        return scope if page_kind.blank?
        return scope unless Page::PAGE_KINDS.include?(page_kind)

        scope.where(page_kind: page_kind)
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
