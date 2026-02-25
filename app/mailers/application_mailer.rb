class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Notae <noreply@notae.local>")
  layout "mailer"
end
