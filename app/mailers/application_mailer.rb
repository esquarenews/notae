class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAIL_FROM", "Notae <noreply@notae.local>")
  layout "mailer"

  private

  def smtp_delivery_options
    user = mailer_user
    return nil if user.blank? || !user.smtp_configured?

    {
      address: user.smtp_address,
      port: user.smtp_port,
      domain: user.smtp_domain.presence || ENV.fetch("APP_HOST", "localhost"),
      user_name: user.smtp_username,
      password: user.smtp_password,
      authentication: user.smtp_authentication.to_s.presence&.to_sym || :plain,
      enable_starttls_auto: user.smtp_enable_starttls_auto?,
      open_timeout: 10,
      read_timeout: 20
    }
  end

  def mail_from_value
    user = mailer_user
    return ENV.fetch("MAIL_FROM", "Notae <noreply@notae.local>") if user.blank? || !user.smtp_configured?

    user.smtp_from_display
  end

  def mailer_user
    raw_user = params[:mailer_user]
    raw_user.is_a?(User) ? raw_user : nil
  end
end
