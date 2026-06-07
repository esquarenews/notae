class EmailUnsubscribesController < ApplicationController
  skip_after_action :verify_pundit_authorization

  def show
    user = User.find_signed!(params[:token].to_s, purpose: :email_unsubscribe)
    user.update!(email_notify_activity: false)
    redirect_to root_path, notice: "Email notifications have been turned off."
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to root_path, alert: "That unsubscribe link is no longer valid."
  end
end
