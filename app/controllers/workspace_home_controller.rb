class WorkspaceHomeController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?
    redirect_to_last_visited_page and return if open_last_visited_page?

    @time_greeting = greeting_for(Time.zone.now)
    @invitation = Invitation.new
    @new_page = Page.new
    @new_database = Database.new
    @memberships = policy_scope(Membership).where(workspace_id: @workspace.id).includes(:user).order(:created_at)
    @recent_pages = policy_scope(Page)
                    .for_workspace(@workspace)
                    .active
                    .includes(cover_image_attachment: :blob)
                    .order(updated_at: :desc)
                    .limit(3)
                    .to_a
    @recent_databases = policy_scope(Database).for_workspace(@workspace).order(updated_at: :desc).limit(3).to_a
    @can_invite = policy(Invitation.new(workspace: @workspace)).create?
    @can_manage_memberships = @memberships.any? { |membership| policy(membership).update? }
    @audit_events = policy_scope(AuditEvent).where(workspace_id: @workspace.id).recent_first.limit(15)
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def greeting_for(time)
    hour = time.hour
    return "Good morning" if hour < 12
    return "Good afternoon" if hour < 18

    "Good evening"
  end

  def open_last_visited_page?
    current_user.open_on_start_preference == "last_visited_page"
  end

  def redirect_to_last_visited_page
    last_page_id = session.dig("notae_last_page_visits", @workspace.id.to_s)
    return unless last_page_id

    last_page = policy_scope(Page).for_workspace(@workspace).active.find_by(id: last_page_id)
    return unless last_page

    redirect_to page_path(workspace_slug: @workspace.slug, id: last_page.id)
  end
end
