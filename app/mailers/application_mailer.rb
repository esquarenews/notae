class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Notae <noreply@notae.local>")
  layout "mailer"

  private

  def mail_from_value
    ENV.fetch("MAIL_FROM", "Notae <noreply@notae.local>")
  end
end
