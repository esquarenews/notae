class EpistulariumMessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_message

  def show
    authorize @message

    redirect_to workspace_epistularium_path(
      workspace_slug: @workspace.slug,
      account_id: @message.epistularium_account_id,
      mailbox: @message.mailbox,
      message_id: @message.id
    )
  end

  def suggest
    authorize @message

    agent_action = Epistularium::DraftSuggestionService.new(
      user: current_user,
      workspace: @workspace,
      message: @message,
      suggestion_type: params[:suggestion_type]
    ).call
    redirect_to agent_action_path(workspace_slug: @workspace.slug, id: agent_action.id), notice: "Draft suggestion created from email.", status: :see_other
  rescue Epistularium::DraftSuggestionService::Error => error
    redirect_to workspace_epistularium_path(
      workspace_slug: @workspace.slug,
      account_id: @message.epistularium_account_id,
      mailbox: @message.mailbox,
      message_id: @message.id
    ), alert: error.message, status: :see_other
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_message
    @message = policy_scope(EpistulariumMessage).for_workspace(@workspace).find(params[:id])
  end
end
