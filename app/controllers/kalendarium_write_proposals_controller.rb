class KalendariumWriteProposalsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_proposal, only: %i[confirm reject]

  def create
    proposal = KalendariumWriteProposal.new(proposal_params.merge(workspace: @workspace, user: current_user, status: "pending"))
    authorize proposal

    if proposal.save
      redirect_to kalendarium_path(kalendarium_redirect_params), notice: "Proposal saved for confirmation."
    else
      redirect_to kalendarium_path(kalendarium_redirect_params), alert: proposal.errors.full_messages.to_sentence
    end
  end

  def confirm
    authorize @proposal, :confirm?

    event = Kalendarium::WriteProposalApplier.new(workspace: @workspace, actor: current_user, proposal: @proposal).call
    @proposal.confirm!(event: event)
    redirect_to kalendarium_path(kalendarium_redirect_params), notice: "Proposal applied."
  rescue Kalendarium::WriteProposalApplier::Error => error
    @proposal.update(status: "failed", error_message: error.message)
    redirect_to kalendarium_path(kalendarium_redirect_params), alert: error.message
  end

  def reject
    authorize @proposal, :reject?
    @proposal.reject!
    redirect_to kalendarium_path(kalendarium_redirect_params), notice: "Proposal rejected."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_proposal
    @proposal = policy_scope(KalendariumWriteProposal).for_workspace(@workspace).find(params[:id])
  end

  def proposal_params
    params.require(:kalendarium_write_proposal).permit(:operation, :proposed_by, :expires_at, payload_json: {})
  end

  def kalendarium_redirect_params
    {
      workspace_slug: @workspace.slug,
      view: params[:view],
      date: params[:date]
    }.tap do |redirect_params|
      redirect_params[:window_start] = params[:window_start].presence if params[:window_start].present?
      redirect_params[:embedded] = "1" if params[:embedded].to_s == "1"
      redirect_params[:task_row_id] = params[:task_row_id].presence if params[:task_row_id].present?
    end
  end
end
