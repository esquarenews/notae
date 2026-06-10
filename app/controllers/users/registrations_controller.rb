module Users
  class RegistrationsController < Devise::RegistrationsController
    REGISTRATION_RATE_LIMIT = 5
    REGISTRATION_RATE_PERIOD = 1.hour

    before_action :reject_registration_honeypot, only: :create
    before_action :throttle_registration, only: :create
    before_action :reject_platform_admin_allowlisted_email, only: :create
    before_action :capture_signup_plan, only: %i[new create]

    private

    def build_resource(hash = {})
      super
      return unless action_name == "create"

      resource.require_self_service_registration_confirmation!
      resource.start_self_service_trial!(plan_key: selected_trial_plan_key)
    end

    def after_inactive_sign_up_path_for(_resource)
      new_user_session_path(confirmation_sent: "1")
    end

    def reject_registration_honeypot
      return if params.dig(resource_name, :website).blank?

      build_rejected_resource("Unable to create this account.")
    end

    def throttle_registration
      return if Notae::RequestRateLimiter.consume!(
        name: "user_registration",
        discriminator: request.remote_ip.to_s,
        limit: REGISTRATION_RATE_LIMIT,
        period: REGISTRATION_RATE_PERIOD
      )

      build_rejected_resource("Too many account creation attempts. Try again later.")
    end

    def reject_platform_admin_allowlisted_email
      return unless User.platform_admin_email_allowlisted?(sign_up_params[:email])

      build_rejected_resource("Email is not available for self-service signup")
    end

    def build_rejected_resource(message)
      build_resource(sign_up_params)
      resource.errors.add(:base, message)
      clean_up_passwords(resource)
      set_minimum_password_length
      respond_with(resource)
    end

    def capture_signup_plan
      requested = params[:plan].presence || params.dig(resource_name, :plan).presence
      return unless Billing::PlanCatalog.public_plan_keys.include?(requested.to_s)

      session[:notae_signup_plan] = requested.to_s
    end

    def selected_trial_plan_key
      requested = params[:plan].presence || params.dig(resource_name, :plan).presence || session[:notae_signup_plan].presence
      Billing::PlanCatalog.public_plan_keys.include?(requested.to_s) ? requested.to_s : WorkspaceSubscription::PLAN_STARTER
    end
  end
end
