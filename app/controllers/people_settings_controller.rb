class PeopleSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  TABS = %w[guests members groups contacts].freeze

  def show
    authorize @workspace, :show?
    @workspace.ensure_join_link_token!
    load_collections
  end

  def update
    authorize @workspace, :update?
    @workspace.ensure_join_link_token!

    if regenerate_join_link?
      @workspace.rotate_join_link_token!
      respond_to do |format|
        format.turbo_stream { render turbo_stream: settings_flash_stream("notice", "New invite link generated.") }
        format.html { redirect_to workspace_people_settings_path(workspace_slug: @workspace.slug), notice: "New invite link generated." }
      end
      return
    end

    if @workspace.update(people_settings_params)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: settings_flash_stream("notice", "People settings updated.") }
        format.html { redirect_to workspace_people_settings_path(workspace_slug: @workspace.slug), notice: "People settings updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: settings_flash_stream("alert", @workspace.errors.full_messages.to_sentence),
                 status: :unprocessable_entity
        end
        format.html { redirect_to workspace_people_settings_path(workspace_slug: @workspace.slug), alert: @workspace.errors.full_messages.to_sentence }
      end
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def load_collections
    memberships = policy_scope(Membership).where(workspace_id: @workspace.id).includes(:user).order(:created_at)
    @guest_memberships, @member_memberships = memberships.partition(&:guest?)
    @tab = TABS.include?(params[:tab].to_s) ? params[:tab].to_s : "guests"
    @can_invite = policy(Invitation.new(workspace: @workspace, invited_by: current_user)).create?
    @invitation = Invitation.new
    @join_link = if @can_invite
      workspace_join_link_url(workspace_slug: @workspace.slug, token: @workspace.join_link_token)
    end
  end

  def people_settings_params
    params.fetch(:workspace, {}).permit(:join_link_enabled)
  end

  def regenerate_join_link?
    params.fetch(:workspace, {}).fetch(:regenerate_join_link, "").to_s == "1"
  end
end
