class InvitationMailer < ApplicationMailer
  def workspace_invitation
    @invitation = params[:invitation]
    @workspace = @invitation.workspace
    @accept_url = invitation_url(@invitation.token)

    mail_attributes = {
      to: @invitation.email,
      subject: "You're invited to #{@workspace.name} on Notae",
      from: mail_from_value
    }
    delivery_options = smtp_delivery_options
    mail_attributes[:delivery_method_options] = delivery_options if delivery_options.present?

    mail(mail_attributes)
  end
end
