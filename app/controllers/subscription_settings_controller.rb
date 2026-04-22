class SubscriptionSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user

  def show
    authorize @workspace, :show?
    authorize @user, :update?
    @subscription = @workspace.subscription_record
    @tenant_snapshot = TenantLimits::Snapshot.new(workspace: @workspace).call
    @billing_provider_ready = Billing::FatZebraGateway.configured?
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_user
    @user = policy_scope(User).find(current_user.id)
  end
end
