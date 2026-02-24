module Api
  module V1
    class BlocksController < BaseController
      before_action :set_workspace!
      before_action :set_page!
      before_action :set_block!, only: %i[show update]

      def index
        blocks = policy_scope(Block).for_page(@page).active.ordered

        render json: { data: Api::V1::Serializers::BlockSerializer.render_collection(blocks) }, status: :ok
      end

      def show
        authorize @block, :show?

        render json: { data: Api::V1::Serializers::BlockSerializer.render(@block) }, status: :ok
      end

      def create
        block = Block.new(block_attributes)
        block.page = @page
        block.workspace = workspace
        block.created_by = current_user
        authorize block, :create?

        block = Api::V1::Blocks::CreateService.call(
          page: @page,
          workspace: workspace,
          actor: current_user,
          attributes: block_attributes
        )
        return render_validation_errors(block) unless block.persisted?

        render json: { data: Api::V1::Serializers::BlockSerializer.render(block) }, status: :created
      end

      def update
        authorize @block, :update?

        block = Api::V1::Blocks::UpdateService.call(block: @block, attributes: block_attributes)
        return render_validation_errors(block) if block.errors.any?

        render json: { data: Api::V1::Serializers::BlockSerializer.render(block) }, status: :ok
      end

      private

      def set_page!
        @page = policy_scope(Page).for_workspace(workspace).find(params[:page_id])
        authorize @page, :show?
      end

      def set_block!
        @block = policy_scope(Block).for_page(@page).find(params[:id])
      end

      def block_attributes
        permitted = params.require(:block).permit(:parent_block_id, :block_type, :embed_url)
        if params[:block].key?(:content_json)
          raw_content = params[:block][:content_json]
          permitted[:content_json] = raw_content.respond_to?(:to_unsafe_h) ? raw_content.to_unsafe_h : raw_content
        end
        permitted.to_h
      end
    end
  end
end
