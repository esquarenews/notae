class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Notae <noreply@notae.local>")
  layout "mailer"

  private

  def mail_from_value
    ENV.fetch("MAIL_FROM", "Notae <noreply@notae.local>")
  end

  def add_list_unsubscribe_headers_for(user)
    return if user.blank?

    token = user.signed_id(purpose: :email_unsubscribe, expires_in: 90.days)
    url = email_unsubscribe_url(token: token)
    headers["List-Unsubscribe"] = "<#{url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
  end
end
