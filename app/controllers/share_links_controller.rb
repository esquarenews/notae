class ShareLinksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_page
  before_action :set_share_link, only: :destroy

  def create
    @share_link = @page.share_links.new(share_link_params)
    @share_link.created_by = current_user
    authorize @share_link

    if @share_link.save
      log_public_share_event!(
        kind: "public_share_link_created",
        share_link_id: @share_link.id,
        expires_at: @share_link.expires_at
      )
      redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Public share link created."
    else
      redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), alert: @share_link.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @share_link
    @share_link.revoke!
    log_public_share_event!(
      kind: "public_share_link_revoked",
      share_link_id: @share_link.id
    )
    redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Public share link revoked."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_page
    @page = policy_scope(Page).for_workspace(@workspace).find(params[:page_id])
  end

  def set_share_link
    @share_link = policy_scope(ShareLink).for_page(@page).find(params[:id])
  end

  def share_link_params
    params.fetch(:share_link, {}).permit(:expires_at)
  end

  def log_public_share_event!(kind:, share_link_id:, expires_at: nil)
    AuditEvent.create!(
      workspace: @workspace,
      actor: current_user,
      action: "share",
      metadata: {
        kind: kind,
        page_id: @page.id,
        share_link_id: share_link_id,
        expires_at: expires_at
      },
      auditable: @page
    )
  end
end
