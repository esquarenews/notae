class WorkspaceJoinLinksController < ApplicationController
  before_action :authenticate_user!

  def show
    workspace = Workspace.active.find_by!(slug: params[:workspace_slug], join_link_token: params[:token], join_link_enabled: true)
    authorize workspace, :join_via_link?

    membership = Membership.find_or_initialize_by(workspace: workspace, user: current_user)
    membership.role = :member if membership.new_record? || membership.guest?
    membership.save!

    redirect_to workspace_path(workspace.slug), notice: "You joined #{workspace.name}."
  end
end
