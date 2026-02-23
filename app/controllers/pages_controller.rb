class PagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_page, only: %i[show archive restore permissions]

  def show
    authorize @page

    @invitation = Invitation.new
    @new_page = Page.new(parent_page: @page)
    @new_root_block = Block.new
    @memberships = policy_scope(Membership).where(workspace_id: @workspace.id).includes(:user).order(:created_at)
    @pages = policy_scope(Page).for_workspace(@workspace).active.order(:created_at).to_a
    @pages_by_parent = @pages.group_by(&:parent_page_id)
    @active_blocks = policy_scope(Block).for_page(@page).active.ordered.to_a
    @blocks_by_parent = @active_blocks.group_by(&:parent_block_id)
    @archived_blocks = policy_scope(Block).for_page(@page).archived.ordered.to_a
    @page_comments = policy_scope(Comment).where(commentable: @page).includes(:author, :resolved_by).order(created_at: :desc)
    @comments_by_block = policy_scope(Comment)
                         .where(commentable_type: "Block", commentable_id: @active_blocks.map(&:id))
                         .includes(:author, :resolved_by)
                         .order(created_at: :desc)
                         .group_by(&:commentable_id)
    @new_page_comment = Comment.new
    @new_block_comment = Comment.new
    @backlinks = policy_scope(PageLink).for_target(@page).includes(:source_page).order(created_at: :desc)
    @can_invite = policy(Invitation.new(workspace: @workspace)).create?
    @can_manage_permissions = policy(@page).permissions?
    @shared_user_ids = @page.page_shares.pluck(:user_id)
    @audit_events = policy_scope(AuditEvent).where(workspace_id: @workspace.id).recent_first.limit(15)
  end

  def create
    @page = @workspace.pages.new(page_params)
    @page.created_by = current_user
    authorize @page

    if @page.save
      redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Page created."
    else
      redirect_back fallback_location: workspace_path(@workspace.slug), alert: @page.errors.full_messages.to_sentence
    end
  end

  def archive
    authorize @page, :archive?
    @page.archive!
    AuditEventLogger.log!(
      workspace: @workspace,
      actor: current_user,
      action: "delete",
      metadata: { kind: "page_archive", page_id: @page.id },
      auditable: @page
    )
    redirect_to workspace_path(@workspace.slug), notice: "Page archived."
  end

  def restore
    authorize @page, :restore?
    @page.restore!
    redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Page restored."
  end

  def permissions
    authorize @page, :permissions?

    permission_mode = params.require(:page).permit(:permission_mode)[:permission_mode]
    shared_user_ids = Array(params.dig(:page, :shared_user_ids)).reject(&:blank?)
    allowed_user_ids =
      if permission_mode == "specific_users"
        @workspace.memberships.where(user_id: shared_user_ids).pluck(:user_id)
      else
        []
      end

    ActiveRecord::Base.transaction do
      @page.update!(permission_mode: permission_mode)

      @page.page_shares.where.not(user_id: allowed_user_ids).delete_all
      allowed_user_ids.each do |user_id|
        @page.page_shares.find_or_create_by!(user_id: user_id) do |share|
          share.created_by = current_user
        end
      end

      AuditEventLogger.log!(
        workspace: @workspace,
        actor: current_user,
        action: "share",
        metadata: {
          kind: "page_permissions_updated",
          page_id: @page.id,
          permission_mode: @page.permission_mode,
          shared_user_ids: allowed_user_ids
        },
        auditable: @page
      )
    end

    redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Page permissions updated."
  rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid => error
    redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), alert: error.message
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_page
    @page = policy_scope(Page).for_workspace(@workspace).find(params[:id])
  end

  def page_params
    params.require(:page).permit(:title, :parent_page_id)
  end
end
