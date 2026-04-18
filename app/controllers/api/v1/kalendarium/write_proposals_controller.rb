module Api
  module V1
    module Kalendarium
      class WriteProposalsController < BaseController
        require_api_token_scopes(
          create: ApiToken::SCOPE_CALENDAR_WRITE,
          confirm: ApiToken::SCOPE_CALENDAR_WRITE,
          reject: ApiToken::SCOPE_CALENDAR_WRITE
        )

        before_action :set_workspace!
        before_action :set_proposal!, only: %i[confirm reject]

        def create
          proposal = ::KalendariumWriteProposal.new(proposal_params.merge(workspace: workspace, user: current_user, status: "pending"))
          authorize proposal, :create?

          return render_validation_errors(proposal) unless proposal.save

          render json: { data: Api::V1::Serializers::KalendariumWriteProposalSerializer.render(proposal) }, status: :created
        end

        def confirm
          authorize @proposal, :confirm?

          event = ::Kalendarium::WriteProposalApplier.new(workspace: workspace, actor: current_user, proposal: @proposal).call
          @proposal.confirm!(event: event)

          render json: { data: Api::V1::Serializers::KalendariumWriteProposalSerializer.render(@proposal) }, status: :ok
        rescue ::Kalendarium::WriteProposalApplier::Error => error
          @proposal.update(status: "failed", error_message: error.message)
          render_error(code: "proposal_failed", message: error.message, status: :unprocessable_entity)
        end

        def reject
          authorize @proposal, :reject?
          @proposal.reject!

          render json: { data: Api::V1::Serializers::KalendariumWriteProposalSerializer.render(@proposal) }, status: :ok
        end

        private

        def set_proposal!
          @proposal = policy_scope(::KalendariumWriteProposal).for_workspace(workspace).find(params[:id])
        end

        def proposal_params
          params.require(:kalendarium_write_proposal).permit(:operation, :proposed_by, :expires_at, :kalendarium_event_id, payload_json: {})
        end
      end
    end
  end
end
