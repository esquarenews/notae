class AccountSettingsMailer < ApplicationMailer
  def account_deletion_requested
    @user = params[:user]
    @workspace = params[:workspace]

    mail(
      to: params[:recipient],
      subject: "Notae account deletion request received",
      from: mail_from_value
    )
  end
end
