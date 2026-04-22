class WorkspacesController < ApplicationController
  before_action :authenticate_user!

  def new
    @workspace = Workspace.new
    authorize @workspace
  end

  def create
    @workspace = Workspace.new(workspace_params)
    authorize @workspace

    ActiveRecord::Base.transaction do
      @workspace.save!
      Membership.create!(workspace: @workspace, user: current_user, role: :owner)
      @workspace.create_workspace_subscription!(
        plan_key: WorkspaceSubscription::PLAN_FREE,
        status: WorkspaceSubscription::STATUS_TRIALING,
        billing_provider: WorkspaceSubscription::PROVIDER_FAT_ZEBRA
      )
    end
    redirect_to workspace_path(@workspace.slug), notice: "Workspace created."
  rescue ActiveRecord::RecordInvalid
    if @workspace.persisted? && !@workspace.users.exists?(current_user.id)
      @workspace.destroy
    end
    if @workspace.errors.empty?
      @workspace.errors.add(:base, "Workspace could not be created.")
    end
    render :new, status: :unprocessable_entity
  end

  private

  def workspace_params
    params.require(:workspace).permit(:name, :slug, :workspace_color)
  end
end
