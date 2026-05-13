module Api
  module V1
    class AgentActionsController < BaseController
      require_api_token_scopes(
        index: ApiToken::SCOPE_AGENT_ACTIONS_READ,
        show: ApiToken::SCOPE_AGENT_ACTIONS_READ,
        create: ApiToken::SCOPE_AGENT_ACTIONS_WRITE,
        approve: ApiToken::SCOPE_AGENT_ACTIONS_WRITE,
        reverse: ApiToken::SCOPE_AGENT_ACTIONS_WRITE
      )

      DEFAULT_LIMIT = 25
      MAX_LIMIT = 100

      before_action :set_workspace!
      before_action :set_agent_action!, only: %i[show approve reverse]

      def index
        authorize AgentAction.new(workspace: workspace, user: current_user), :index?

        agent_actions = policy_scope(AgentAction).for_workspace(workspace).recent_first
        agent_actions = apply_status_filter(agent_actions)
        agent_actions = agent_actions.limit(result_limit)

        render json: {
          data: Api::V1::Serializers::AgentActionSerializer.render_collection(agent_actions)
        }, status: :ok
      end

      def show
        authorize @agent_action, :show?

        render json: {
          data: Api::V1::Serializers::AgentActionSerializer.render(@agent_action, include_history: true)
        }, status: :ok
      end

      def create
        agent_action = AgentAction.new(
          workspace: workspace,
          user: current_user,
          title: agent_action_params.fetch(:title),
          proposed_by: agent_action_params[:proposed_by].presence || "api",
          target_system: agent_action_params.fetch(:target_system),
          draft_type: agent_action_params.fetch(:draft_type),
          payload_json: agent_action_params.fetch(:payload_json, {}),
          metadata_json: agent_action_params.fetch(:metadata_json, {})
        )
        authorize agent_action, :create?

        agent_action = AgentActions::DraftCreator.new(
          workspace: workspace,
          actor: current_user,
          attributes: {
            title: agent_action.title,
            proposed_by: agent_action.proposed_by,
            target_system: agent_action.target_system,
            draft_type: agent_action.draft_type,
            payload_json: agent_action.payload_json,
            metadata_json: agent_action.metadata_json
          }
        ).call

        render json: {
          data: Api::V1::Serializers::AgentActionSerializer.render(agent_action, include_history: true)
        }, status: :created
      rescue AgentActions::DraftCreator::Error => error
        render_error(code: "validation_failed", message: error.message, status: :unprocessable_entity)
      end

      def approve
        authorize @agent_action, :approve?

        agent_action = AgentActions::ApprovalService.new(
          agent_action: @agent_action,
          actor: current_user,
          comment: approval_params[:decision_comment],
          destination_database_id: approval_params[:destination_database_id],
          destination_calendar_id: approval_params[:destination_calendar_id]
        ).call

        render json: {
          data: Api::V1::Serializers::AgentActionSerializer.render(agent_action.reload, include_history: true)
        }, status: :ok
      rescue AgentActions::ApprovalService::Error => error
        render_error(code: "validation_failed", message: error.message, status: :unprocessable_entity)
      end

      def reverse
        authorize @agent_action, :reverse?

        agent_action = AgentActions::ReversalService.new(
          agent_action: @agent_action,
          actor: current_user,
          comment: params[:decision_comment]
        ).call

        render json: {
          data: Api::V1::Serializers::AgentActionSerializer.render(agent_action.reload, include_history: true)
        }, status: :ok
      rescue AgentActions::ReversalService::Error => error
        render_error(code: "validation_failed", message: error.message, status: :unprocessable_entity)
      end

      private

      def set_agent_action!
        @agent_action = policy_scope(AgentAction).for_workspace(workspace).find(params[:id])
      end

      def apply_status_filter(scope)
        status = params[:status].to_s.strip
        return scope if status.blank?
        return scope unless AgentAction::STATUS_OPTIONS.include?(status)

        scope.where(status: status)
      end

      def result_limit
        requested_limit = params[:limit].to_i
        return DEFAULT_LIMIT if requested_limit <= 0

        [ requested_limit, MAX_LIMIT ].min
      end

      def agent_action_params
        params.require(:agent_action).permit(
          :title,
          :proposed_by,
          :target_system,
          :draft_type,
          payload_json: {},
          metadata_json: {}
        )
      end

      def approval_params
        params.permit(:decision_comment, :destination_database_id, :destination_calendar_id)
      end
    end
  end
end
