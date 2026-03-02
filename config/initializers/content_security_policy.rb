# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.frame_ancestors :self
    # Allow OAuth form redirects to Google's authorization endpoint.
    policy.form_action :self, "https://accounts.google.com"
    policy.object_src :none
    policy.script_src :self, :https
    policy.style_src :self, :https, :unsafe_inline
    policy.font_src :self, :https, :data
    policy.img_src :self, :https, :data, :blob
    policy.connect_src :self, :https, "wss:", "ws:"
    policy.worker_src :self, :blob
    policy.frame_src :self
  end

  # Generate nonces for importmap-managed inline scripts.
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true
end
