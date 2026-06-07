class HomeController < ApplicationController
  def index
    @workspaces = policy_scope(Workspace).where.not(slug: [ nil, "" ]).order(:name)
    if user_signed_in?
      workspace = @workspaces.first
      redirect_to workspace_path(workspace.slug) and return if workspace.present?
    end

    @public_plans = Billing::PlanCatalog.public_plan_keys
  end
end
