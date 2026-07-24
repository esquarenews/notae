class WorkspacesController < ApplicationController
  before_action :authenticate_user!

  def new
    @workspace = Workspace.new
    @selected_plan_key = selected_plan_key
    @workspace_creation_entitlement = workspace_creation_entitlement
    authorize @workspace
  end

  def create
    @workspace = Workspace.new(workspace_params)
    entitlement = workspace_creation_entitlement
    authorize @workspace

    ActiveRecord::Base.transaction do
      @workspace.save!
      Membership.create!(workspace: @workspace, user: current_user, role: :owner)
      @workspace.create_workspace_subscription!(entitlement.subscription_attributes)
      record_account_covered_workspace_creation!(@workspace, entitlement) unless entitlement.requires_checkout?
    end

    if entitlement.requires_checkout?
      redirect_to_stripe_checkout!(@workspace)
    else
      redirect_to workspace_path(@workspace.slug), notice: "Workspace created under your unlimited account."
    end
  rescue ActiveRecord::RecordInvalid, Billing::StripeGateway::ConfigurationError, Stripe::StripeError => error
    if @workspace.persisted? && !@workspace.users.exists?(current_user.id)
      @workspace.destroy
    end
    if @workspace.errors.empty?
      @workspace.errors.add(:base, error.message.presence || "Workspace could not be created.")
    end
    @selected_plan_key = selected_plan_key
    @workspace_creation_entitlement = workspace_creation_entitlement
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

  def workspace_creation_entitlement
    Billing::WorkspaceCreationEntitlement.new(
      user: current_user,
      requested_plan_key: selected_plan_key
    )
  end

  def record_account_covered_workspace_creation!(workspace, entitlement)
    AdminAuditEvent.create!(
      actor: current_user,
      workspace: workspace,
      target: workspace.workspace_subscription,
      action: "workspace_created_under_account_plan",
      metadata_json: {
        account_plan_key: current_user.saas_plan_key,
        workspace_plan_key: entitlement.plan_key,
        workspace_limit: current_user.workspace_limit_label
      }
    )
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
