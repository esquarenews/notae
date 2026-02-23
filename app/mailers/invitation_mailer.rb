class InvitationMailer < ApplicationMailer
  def workspace_invitation
    @invitation = params[:invitation]
    @workspace = @invitation.workspace
    @accept_url = invitation_url(@invitation.token)

    mail(
      to: @invitation.email,
      subject: "You're invited to #{@workspace.name} on Notae"
    )
  end
end
