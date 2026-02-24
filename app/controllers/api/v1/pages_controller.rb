module Api
  module V1
    class PagesController < BaseController
      before_action :set_workspace!
      before_action :set_page!, only: %i[show update]

      def index
        pages = policy_scope(Page).for_workspace(workspace).active.order(:created_at)

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
    end
  end
end
