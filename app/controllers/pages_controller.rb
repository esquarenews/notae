class PagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_page, only: %i[show update duplicate archive restore permissions destroy]
  COVER_SHIFT_STEP = 10

  def show
    authorize @page
    remember_last_page_visit!

    @memberships = policy_scope(Membership).where(workspace_id: @workspace.id).includes(:user).order(:created_at)
    @pages = policy_scope(Page).for_workspace(@workspace).active.order(:created_at).to_a
    @move_target_pages = @pages.reject { |candidate| candidate.id == @page.id }

    @active_blocks = policy_scope(Block).for_page(@page).active.ordered.to_a
    if @active_blocks.empty? && policy(Block.new(workspace: @workspace, page: @page, created_by: current_user)).create?
      @page.blocks.create!(workspace: @workspace, created_by: current_user, block_type: "paragraph")
      @active_blocks = policy_scope(Block).for_page(@page).active.ordered.to_a
    end
    @blocks_by_parent = @active_blocks.group_by(&:parent_block_id)
    @archived_blocks = policy_scope(Block).for_page(@page).archived.ordered.to_a
    @can_manage_permissions = policy(@page).permissions?
    @can_archive_page = policy(@page).archive?
    @shared_user_ids = @page.page_shares.pluck(:user_id)
    @backlinks = policy_scope(PageLink).for_target(@page).includes(:source_page).order(created_at: :desc)
    @page_exports = policy_scope(PageExport).for_page(@page).recent_first.limit(10).to_a
    @page_templates = policy_scope(PageTemplate).for_workspace(@workspace).recent_first.limit(20).to_a
    @recent_audit_events = policy_scope(AuditEvent)
                             .where(workspace_id: @workspace.id, auditable: @page)
                             .recent_first
                             .limit(10)
                             .to_a
    @new_page_template = PageTemplate.new
    @page_versions = @page.versions.reorder(created_at: :desc).limit(10).to_a
    @share_links =
      if @can_manage_permissions
        policy_scope(ShareLink).for_page(@page).recent_first.to_a
      else
        []
      end
    @can_update_page = policy(@page).update?
    page_comment_probe = Comment.new(commentable: @page, workspace: @workspace, author: current_user, body: "draft")
    @can_comment_on_page = policy(page_comment_probe).create?
    @new_page_comment = Comment.new
    @page_comments = policy_scope(Comment)
                       .for_workspace(@workspace)
                       .where(commentable: @page)
                       .includes(:author, :resolved_by)
                       .order(created_at: :desc)
                       .to_a
    @page_plain_text = @active_blocks.filter_map { |block| block.search_text.to_s.strip.presence }.join("\n")
    @page_word_count = @page_plain_text.scan(/\b[\p{L}\p{N}'-]+\b/u).size
    @page_favorite = policy_scope(Favorite).for_workspace(@workspace).for_user(current_user).find_by(favoritable: @page)
  end

  def update
    authorize @page, :update?

    @page.assign_attributes(page_update_params)
    apply_header_customizations!

    if @page.changed?
      @page.save
    else
      true
    end

    if @page.errors.empty?
      respond_to do |format|
        format.html { redirect_to page_redirect_path, notice: "Page updated." }
        format.json do
          render json: {
            id: @page.id,
            title: @page.title,
            icon: @page.icon,
            updated_at: @page.updated_at&.iso8601(6)
          }, status: :ok
        end
      end
    else
      respond_to do |format|
        format.html do
          redirect_to page_redirect_path, alert: @page.errors.full_messages.to_sentence
        end
        format.json { render json: { errors: @page.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def duplicate
    authorize @page, :show?
    authorize Page.new(workspace: @workspace, created_by: current_user, title: "#{@page.title} (copy)"), :create?

    duplicated_page = Pages::DuplicateService.call(page: @page, created_by: current_user, title: params.dig(:page, :title))

    redirect_to page_redirect_path(duplicated_page.id), notice: "Page duplicated."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to page_redirect_path, alert: error.record.errors.full_messages.to_sentence
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

  def destroy
    authorize @page, :destroy?

    unless @page.archived?
      redirect_to workspace_trash_path(workspace_slug: @workspace.slug), alert: "Archive the page before deleting it permanently."
      return
    end

    @page.destroy!
    redirect_to workspace_trash_path(workspace_slug: @workspace.slug), notice: "Page deleted permanently."
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

    redirect_to page_redirect_path, notice: "Page permissions updated."
  rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid => error
    redirect_to page_redirect_path, alert: error.message
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

  def page_update_params
    permitted = params.fetch(:page, ActionController::Parameters.new)
                      .permit(:title, :parent_page_id, :font_style, :small_text, :full_width, :locked, :suggest_edits)

    permitted[:parent_page_id] = nil if permitted[:parent_page_id].blank?
    permitted.delete(:locked) unless policy(@page).permissions?
    permitted
  end

  def page_header_params
    params.fetch(:page, ActionController::Parameters.new)
          .permit(:icon, :icon_action, :cover_action, :cover_shift, :cover_focal_y, :cover_image, :cover_preset_key)
  end

  def apply_header_customizations!
    payload = page_header_params
    apply_icon_update!(payload)
    apply_cover_update!(payload)
  end

  def apply_icon_update!(payload)
    case payload[:icon_action]
    when "set"
      emoji = payload[:icon].to_s.strip
      @page.icon = emoji.presence
    when "clear"
      @page.icon = nil
    end
  end

  def apply_cover_update!(payload)
    case payload[:cover_action]
    when "random"
      @page.cover_preset_key = Page::COVER_PRESET_KEYS.sample
      @page.cover_image.purge if @page.cover_image.attached?
    when "preset"
      requested_key = payload[:cover_preset_key].to_s
      if Page::COVER_PRESET_KEYS.include?(requested_key)
        @page.cover_preset_key = requested_key
        @page.cover_image.purge if @page.cover_image.attached?
      end
    when "upload"
      if payload[:cover_image].present?
        @page.cover_image.attach(payload[:cover_image])
        @page.cover_preset_key = nil
      end
    when "clear"
      @page.cover_preset_key = nil
      @page.cover_image.purge if @page.cover_image.attached?
    end

    shift_delta = { "up" => -COVER_SHIFT_STEP, "down" => COVER_SHIFT_STEP }[payload[:cover_shift].to_s]
    if shift_delta
      base = @page.cover_focal_y || 50
      @page.cover_focal_y = (base + shift_delta).clamp(0, 100)
    elsif payload[:cover_focal_y].present?
      @page.cover_focal_y = payload[:cover_focal_y].to_i.clamp(0, 100)
    end
  end

  def page_redirect_path(page_id = @page.id, anchor: nil)
    redirect_params = { workspace_slug: @workspace.slug, id: page_id }.merge(open_menu_query_params)
    redirect_params[:anchor] = anchor if anchor.present?
    page_path(redirect_params)
  end

  def open_menu_query_params
    query = {}
    query[:actions_menu] = "open" if params[:actions_menu].to_s == "open"
    query[:options_menu] = "open" if params[:options_menu].to_s == "open"
    query
  end

  def remember_last_page_visit!
    store = session["notae_last_page_visits"]
    store = {} unless store.is_a?(Hash)
    store[@workspace.id.to_s] = @page.id.to_s
    session["notae_last_page_visits"] = store
  end
end
