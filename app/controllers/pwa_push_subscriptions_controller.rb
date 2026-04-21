class PwaPushSubscriptionsController < ApplicationController
  before_action :authenticate_user!

  def create
    authorize current_user, :update?

    endpoint = subscription_params.fetch(:endpoint)
    keys = subscription_keys
    raise ActionController::ParameterMissing, "subscription.keys.p256dh" if keys[:p256dh].blank?
    raise ActionController::ParameterMissing, "subscription.keys.auth" if keys[:auth].blank?

    subscription = WebPushSubscription.find_or_initialize_by(endpoint: endpoint)
    subscription.user = current_user
    subscription.p256dh = keys.fetch(:p256dh)
    subscription.auth = keys.fetch(:auth)
    subscription.expiration_time = normalized_expiration_time(subscription_params[:expiration_time])
    subscription.user_agent = request.user_agent.to_s
    subscription.last_error_at = nil
    subscription.last_error_message = nil
    subscription.save!

    render json: { ok: true, id: subscription.id }
  rescue ActionController::ParameterMissing => error
    render json: { ok: false, error: error.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => error
    render json: { ok: false, error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def destroy
    authorize current_user, :update?

    endpoint = params[:endpoint].to_s.strip
    return head :unprocessable_entity if endpoint.blank?

    current_user.web_push_subscriptions.find_by(endpoint: endpoint)&.destroy!
    head :no_content
  end

  private

  def subscription_params
    params.require(:subscription).permit(:endpoint, :expiration_time, keys: %i[p256dh auth])
  end

  def subscription_keys
    subscription_params.fetch(:keys, {}).to_h.symbolize_keys
  end

  def normalized_expiration_time(raw_value)
    return nil if raw_value.blank?

    milliseconds = Float(raw_value)
    Time.at(milliseconds / 1000.0)
  rescue ArgumentError, TypeError
    nil
  end
end
