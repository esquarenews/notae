class InvitationsController < ApplicationController
  before_action :authenticate_user!, only: %i[create accept]
  before_action :set_workspace, only: :create
  before_action :set_invitation, only: %i[show accept]

  def create
    @invitation = @workspace.invitations.new(invitation_params)
    @invitation.invited_by = current_user
    authorize @invitation

    if @invitation.save
      InvitationMailer.with(invitation: @invitation).workspace_invitation.deliver_later
      redirect_to workspace_path(@workspace.slug), notice: "Invitation sent."
    else
      redirect_to workspace_path(@workspace.slug), alert: @invitation.errors.full_messages.to_sentence
    end
  end

  def show
    authorize @invitation, :show?
  end

  def accept
    authorize @invitation, :accept?

    if !@invitation.pending?
      redirect_to invitation_path(@invitation.token), alert: "Invitation is no longer valid."
      return
    end

    @invitation.accept!(current_user)
    redirect_to workspace_path(@invitation.workspace.slug), notice: "You joined #{@invitation.workspace.name}."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to invitation_path(@invitation.token), alert: e.record.errors.full_messages.to_sentence
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_invitation
    @invitation = Invitation.find_by!(token: params[:token])
  end

  def invitation_params
    params.require(:invitation).permit(:email, :role)
  end
end
