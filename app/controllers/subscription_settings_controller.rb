class SubscriptionSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user

  def show
    authorize @workspace, :manage_billing?
    authorize @user, :update?
    @subscription = @workspace.subscription_record
    @tenant_snapshot = TenantLimits::Snapshot.new(workspace: @workspace).call
    @billing_provider_ready = Billing::StripeGateway.configured?
  end

  def portal
    authorize @workspace, :manage_billing?

    session = Billing::StripeGateway.new(subscription: @workspace.subscription_record, user: current_user)
      .create_portal_session!(return_url: workspace_subscription_settings_url(workspace_slug: @workspace.slug))
    redirect_to session.url, allow_other_host: true
  rescue Billing::StripeGateway::ConfigurationError, Stripe::StripeError => error
    redirect_to workspace_subscription_settings_path(workspace_slug: @workspace.slug), alert: error.message
  end

  def cancel
    authorize @workspace, :manage_billing?

    Billing::StripeGateway.new(subscription: @workspace.subscription_record, user: current_user).cancel_at_period_end!
    AdminAuditEvent.create!(
      actor: current_user,
      workspace: @workspace,
      target: @workspace.subscription_record,
      action: "subscription_canceled",
      metadata_json: { cancel_at_period_end: true }
    )
    redirect_to workspace_subscription_settings_path(workspace_slug: @workspace.slug),
                notice: "Subscription cancellation scheduled for the end of the billing period."
  rescue Billing::StripeGateway::ConfigurationError, Stripe::StripeError => error
    redirect_to workspace_subscription_settings_path(workspace_slug: @workspace.slug), alert: error.message
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_user
    @user = policy_scope(User).find(current_user.id)
  end
end
