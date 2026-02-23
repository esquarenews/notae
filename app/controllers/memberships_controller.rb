class MembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_membership

  def update
    authorize @membership

    role_attributes = membership_params
    if role_attributes.blank?
      redirect_to workspace_path(@workspace.slug), alert: "Role is invalid."
      return
    end

    previous_role = @membership.role
    if @membership.update(role_attributes)
      if previous_role != @membership.role
        AuditEventLogger.log!(
          workspace: @workspace,
          actor: current_user,
          action: "role_change",
          metadata: {
            membership_id: @membership.id,
            changed_user_id: @membership.user_id,
            from_role: previous_role,
            to_role: @membership.role
          },
          auditable: @membership
        )
      end
      redirect_to workspace_path(@workspace.slug), notice: "Membership updated."
    else
      redirect_to workspace_path(@workspace.slug), alert: @membership.errors.full_messages.to_sentence
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_membership
    @membership = policy_scope(Membership).where(workspace_id: @workspace.id).find(params[:id])
  end

  def membership_params
    requested_role = params.dig(:membership, :role).to_s
    return {} unless Membership.roles.key?(requested_role)

    { role: requested_role }
  end
end
