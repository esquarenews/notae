module Users
  class SessionsController < Devise::SessionsController
    def create
      params[resource_name] ||= {}
      if is_navigational_format? && !params[resource_name].key?(:remember_me)
        params[resource_name][:remember_me] = "1"
      end

      self.resource = warden.authenticate(auth_options)

      if resource
        set_flash_message!(:notice, :signed_in)
        sign_in(resource_name, resource)
        log_session_diagnostic_event(
          reason: "signed_in",
          extra: {
            auth_source: "password",
            remember_me_requested: ActiveModel::Type::Boolean.new.cast(params.dig(resource_name, :remember_me))
          }
        )
        yield resource if block_given?
        respond_with resource, location: after_sign_in_path_for(resource)
      else
        log_session_diagnostic_event(reason: "failed_authentication", extra: { auth_source: "password" })
        flash[:alert] = I18n.t("devise.failure.invalid", authentication_keys: resource_class.authentication_keys.join("/"))
        redirect_to new_session_path(resource_name), status: :see_other
      end
    end

    def destroy
      log_session_diagnostic_event(reason: "signed_out", extra: { auth_source: "session" }) if current_user.present?
      super
    end
  end
end
