class WorkspacesController < ApplicationController
  before_action :authenticate_user!

  def new
    @workspace = Workspace.new
    @selected_plan_key = selected_plan_key
    authorize @workspace
  end

  def create
    @workspace = Workspace.new(workspace_params)
    plan_key = selected_plan_key
    authorize @workspace

    ActiveRecord::Base.transaction do
      @workspace.save!
      Membership.create!(workspace: @workspace, user: current_user, role: :owner)
      @workspace.create_workspace_subscription!(
        plan_key: plan_key,
        status: WorkspaceSubscription::STATUS_INCOMPLETE,
        billing_provider: WorkspaceSubscription::PROVIDER_STRIPE
      )
    end
    redirect_to_stripe_checkout!(@workspace)
  rescue ActiveRecord::RecordInvalid, Billing::StripeGateway::ConfigurationError, Stripe::StripeError => error
    if @workspace.persisted? && !@workspace.users.exists?(current_user.id)
      @workspace.destroy
    end
    if @workspace.errors.empty?
      @workspace.errors.add(:base, error.message.presence || "Workspace could not be created.")
    end
    @selected_plan_key = selected_plan_key
    render :new, status: :unprocessable_entity
  end

  private

  def workspace_params
    params.require(:workspace).permit(:name, :slug, :workspace_color)
  end

  def selected_plan_key
    requested = params.dig(:workspace, :plan_key).presence || params[:plan].presence || session[:notae_signup_plan].presence
    Billing::PlanCatalog.public_plan_keys.include?(requested.to_s) ? requested.to_s : WorkspaceSubscription::PLAN_STARTER
  end

  def redirect_to_stripe_checkout!(workspace)
    subscription = workspace.workspace_subscription
    checkout_session = Billing::StripeGateway.new(subscription: subscription, user: current_user).create_checkout_session!(
      success_url: billing_checkout_success_url(session_id: "{CHECKOUT_SESSION_ID}"),
      cancel_url: billing_checkout_cancel_url(plan: subscription.plan_key)
    )
    AdminAuditEvent.create!(
      actor: current_user,
      workspace: workspace,
      target: subscription,
      action: "subscription_checkout_started",
      metadata_json: { plan_key: subscription.plan_key, stripe_checkout_session_id: checkout_session.id }
    )
    redirect_to checkout_session.url, allow_other_host: true, status: :see_other
  end
end
