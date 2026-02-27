module Users
  class SessionsController < Devise::SessionsController
    def create
      self.resource = warden.authenticate(auth_options)

      if resource
        set_flash_message!(:notice, :signed_in)
        sign_in(resource_name, resource)
        yield resource if block_given?
        respond_with resource, location: after_sign_in_path_for(resource)
      else
        flash[:alert] = I18n.t("devise.failure.invalid", authentication_keys: resource_class.authentication_keys.join("/"))
        redirect_to new_session_path(resource_name), status: :see_other
      end
    end
  end
end
