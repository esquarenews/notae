class PagesController < ApplicationController
  include RequestPerformanceInstrumentation

  track_request_performance_for :show, :update

  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_page, only: %i[show update duplicate archive restore permissions move_workspace destroy remove_tab import panel]
  COVER_SHIFT_STEP = 10

  def show
    authorize @page
    remember_last_page_visit!
    @page_tabs = resolve_page_tabs
    @split_page = resolve_split_page
    @page_title_page = @page.parent_page || @page
    @can_update_page_title_page = policy(@page_title_page).update?

    @can_create_block = policy(Block.new(workspace: @workspace, page: @page, created_by: current_user)).create?
    page_render_context = build_page_render_context
    if page_render_context.active_blocks.empty? && @can_create_block
      starter_block = @page.blocks.create!(workspace: @workspace, created_by: current_user, block_type: "paragraph")
      page_render_context = page_render_context_with_starter_block(starter_block)
    end

    @active_blocks = page_render_context.active_blocks
    @blocks_by_parent = page_render_context.blocks_by_parent
    @backlinks = policy_scope(PageLink).for_target(@page).includes(source_page: :linked_database).order(created_at: :desc)
    @row_backlink_databases = resolve_row_backlink_databases
    @can_comment_on_page = can_comment_on_page?
    @page_favorite = policy_scope(Favorite).for_workspace(@workspace).for_user(current_user).find_by(favoritable: @page)
    @page_reader_mode = page_render_context.reader_mode
    @can_create_tab_page =
      if @page_tabs.group_page.present?
        policy(Page.new(workspace: @workspace, created_by: current_user, parent_page: @page_tabs.group_page, title: "New tab")).create?
      else
        false
      end
  end

  def panel
    authorize @page, :show?

    case params[:panel].to_s
    when "comments"
      return head :forbidden if @page.locked?

      prepare_page_comments_panel!
      render partial: "pages/comments_menu_body",
             locals: {
               workspace: @workspace,
               page: @page,
               can_comment_on_page: @can_comment_on_page,
               new_page_comment: @new_page_comment,
               page_comments: @page_comments
             }
    when "actions"
      prepare_page_actions_panel!
      render partial: "pages/actions_menu_body",
             locals: {
               workspace: @workspace,
               page: @page,
               can_import_page: policy(@page).update?,
               current_path: params[:current_path].presence || page_path(workspace_slug: @workspace.slug, id: @page.id),
               move_target_pages: @move_target_pages,
               can_manage_permissions: policy(@page).permissions?,
               can_archive_page: policy(@page).archive?,
               page_plain_text: @page_plain_text,
               page_word_count: @page_word_count,
               page_versions: @page_versions,
               recent_audit_events: @recent_audit_events
             }
    when "options"
      return head :forbidden if @page.locked?

      prepare_page_options_panel!
      render partial: "pages/options_menu_body",
             locals: {
               workspace: @workspace,
               page: @page,
               can_manage_permissions: @can_manage_permissions,
               memberships: @memberships,
               shared_user_ids: @shared_user_ids,
               share_links: @share_links,
               page_exports: @page_exports,
               new_page_template: @new_page_template,
               page_templates: @page_templates,
               archived_blocks: @archived_blocks,
               can_move_page: @can_move_page,
               move_workspace_options: @move_workspace_options
             }
    else
      head :not_found
    end
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
        format.html { redirect_to page_return_path(default: page_redirect_path), notice: "Page updated." }
        format.json do
          render json: {
            id: @page.id,
            title: @page.title,
            icon: @page.icon,
            font_style: @page.font_style,
            small_text: @page.small_text?,
            full_width: @page.full_width?,
            remove_blocks: @page.remove_blocks?,
            locked: @page.locked?,
            suggest_edits: @page.suggest_edits?,
            updated_at: @page.updated_at&.iso8601(6),
            sidebar_sections_url: workspace_sidebar_sections_path(workspace_slug: @workspace.slug)
          }, status: :ok
        end
      end
    else
      respond_to do |format|
        format.html do
          redirect_to page_return_path(default: page_redirect_path), alert: @page.errors.full_messages.to_sentence
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
    Pages::VisualDefaultsService.apply(record: @page, source: @page.parent_page)
    authorize @page

    if @page.save
      redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Page created."
    else
      redirect_back fallback_location: workspace_path(@workspace.slug), alert: @page.errors.full_messages.to_sentence
    end
  end

  def import
    authorize @page, :update?

    result = Pages::ImportContentService.call(
      page: @page,
      workspace: @workspace,
      user: current_user,
      files: params.dig(:import, :files),
      insert_after_id: params.dig(:import, :insert_after_id)
    )

    notice = nil
    alert = nil

    if result.imported_count.positive?
      notice = "Imported #{result.imported_count} #{'block'.pluralize(result.imported_count)}."
      warnings = [ result.skipped_message, result.error_message ].compact
      notice = [ notice, warnings.join(" ") ].join(" ") if warnings.any?
    else
      alert = result.error_message || result.skipped_message || "Choose at least one supported file to import."
    end

    redirect_to page_return_path(default: page_redirect_path), notice:, alert:
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

  def remove_tab
    authorize @page, :archive?

    if @page.parent_page.blank?
      redirect_to page_redirect_path, alert: "Only sub-pages can be removed as tabs."
      return
    end

    linked_database_ids = policy_scope(Database).for_workspace(@workspace).where(linked_page_id: @page.id).pluck(:id)

    ActiveRecord::Base.transaction do
      policy_scope(Database).for_workspace(@workspace).where(id: linked_database_ids).find_each do |database|
        database.update!(linked_page: nil)
      end

      @page.archive!
      AuditEventLogger.log!(
        workspace: @workspace,
        actor: current_user,
        action: "delete",
        metadata: {
          kind: "page_tab_removed",
          page_id: @page.id,
          linked_database_ids: linked_database_ids
        },
        auditable: @page
      )
    end

    redirect_to remove_tab_redirect_path(linked_database_ids), notice: "Tab removed."
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

  def move_workspace
    authorize @page, :move_workspace?
    target_workspace = move_target_workspace!
    authorize Page.new(workspace: target_workspace, created_by: current_user, title: @page.title), :create?

    Documents::WorkspaceMoveService.call(record: @page, target_workspace:, actor: current_user)

    redirect_to page_path(workspace_slug: target_workspace.slug, id: @page.id), notice: "Nota moved to #{target_workspace.name}."
  rescue ActionController::ParameterMissing, ActiveRecord::RecordNotFound, Documents::WorkspaceMoveService::Error, ActiveRecord::RecordInvalid => error
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
    params.require(:page).permit(:title, :parent_page_id, :page_kind)
  end

  def page_update_params
    permitted = params.fetch(:page, ActionController::Parameters.new)
                      .permit(:title, :root_tab_title, :parent_page_id, :font_style, :small_text, :full_width, :remove_blocks, :locked, :suggest_edits, :tab_color)

    if permitted.key?(:parent_page_id)
      permitted[:parent_page_id] = nil if permitted[:parent_page_id].blank?
    end
    permitted.delete(:locked) unless policy(@page).permissions?
    permitted
  end

  def page_header_params
    params.fetch(:page, ActionController::Parameters.new)
          .permit(:icon, :icon_action, :cover_action, :cover_shift, :cover_focal_y, :cover_image, :cover_preset_key, :cover_asset_id, :cover_remote_id)
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
    CoverAssets::ApplyService.call(record: @page, workspace: @workspace, user: current_user, payload:)
  end

  def page_redirect_path(page_id = @page.id, anchor: nil, split_page_id: nil, split_source: nil)
    redirect_params = { workspace_slug: @workspace.slug, id: page_id }.merge(open_menu_query_params)
    redirect_params[:embedded] = "1" if embedded_page_shell?
    redirect_params[:split_page_id] = split_page_id || params[:split_page_id].presence
    redirect_params[:split_source] = split_source || params[:split_source].presence
    redirect_params[:anchor] = anchor if anchor.present?
    page_path(redirect_params)
  end

  def page_return_path(default:)
    safe_return_to_path || default
  end

  def open_menu_query_params
    query = {}
    query[:actions_menu] = "open" if params[:actions_menu].to_s == "open"
    query[:options_menu] = "open" if params[:options_menu].to_s == "open"
    query
  end

  def embedded_page_shell?
    params[:embedded].to_s == "1"
  end

  def safe_return_to_path
    candidate = params[:return_to].to_s
    return nil if candidate.blank?
    return nil unless candidate.start_with?("/")
    return nil if candidate.start_with?("//")

    candidate
  end

  def remove_tab_redirect_path(linked_database_ids)
    candidate = safe_return_to_path
    deleted_base_paths = [ page_path(workspace_slug: @workspace.slug, id: @page.id) ]
    deleted_base_paths.concat(linked_database_ids.map { |database_id| database_path(workspace_slug: @workspace.slug, id: database_id) })

    if candidate.present? && !deleted_base_paths.include?(candidate.to_s.split(/[?#]/, 2).first)
      return candidate
    end

    if @page.parent_page_id.present?
      parent_page = policy_scope(Page).for_workspace(@workspace).active.includes(:linked_database).find_by(id: @page.parent_page_id)
      if parent_page.present?
        if parent_page.linked_database.present?
          return database_path(workspace_slug: @workspace.slug, id: parent_page.linked_database.id)
        end

        return page_path(workspace_slug: @workspace.slug, id: parent_page.id, embedded: "1") if embedded_page_shell?
        return page_path(workspace_slug: @workspace.slug, id: parent_page.id)
      end
    end

    workspace_path(@workspace.slug)
  end

  def remember_last_page_visit!
    remember_last_page_visit_for!(workspace: @workspace, page: @page)
  end

  def resolve_page_tabs
    PageTabs::Resolver.new(
      workspace: @workspace,
      page_scope: policy_scope(Page),
      database_scope: policy_scope(Database),
      group_page: @page.parent_page || @page,
      current_page: @page
    ).call
  end

  def resolve_split_page
    split_page_id = params[:split_page_id].presence
    return nil if split_page_id.blank?
    return nil if split_page_id == @page.id

    policy_scope(Page).for_workspace(@workspace).active.find_by(id: split_page_id)
  end

  def resolve_row_backlink_databases
    policy_scope(Database)
      .for_workspace(@workspace)
      .active
      .joins(:db_rows)
      .where(db_rows: { linked_page_id: @page.id, archived_at: nil })
      .includes(:linked_page)
      .distinct
      .order(updated_at: :desc)
      .to_a
  end

  def build_page_render_context
    Pages::RenderContextBuilder.new(
      page: @page,
      block_scope: policy_scope(Block)
    ).call
  end

  def page_render_context_with_starter_block(starter_block)
    Pages::RenderContextBuilder::Result.new(
      active_blocks: [ starter_block ],
      blocks_by_parent: { nil => [ starter_block ] },
      block_lookup: { starter_block.id => starter_block },
      indexes: { starter_block.id => 0 },
      reader_mode: @page.remove_blocks? || @page.locked?
    )
  end

  def can_comment_on_page?
    page_comment_probe = Comment.new(commentable: @page, workspace: @workspace, author: current_user, body: "draft")
    policy(page_comment_probe).create?
  end

  def prepare_page_comments_panel!
    @can_comment_on_page = can_comment_on_page?
    @new_page_comment = Comment.new
    @page_comments = policy_scope(Comment)
                       .for_workspace(@workspace)
                       .where(commentable: @page)
                       .includes(:author, :resolved_by)
                       .order(created_at: :desc)
                       .to_a
  end

  def prepare_page_actions_panel!
    @move_target_pages = policy_scope(Page)
                           .for_workspace(@workspace)
                           .active
                           .order(:created_at)
                           .reject { |candidate| candidate.id == @page.id }
    block_search_texts = policy_scope(Block).for_page(@page).active.ordered.pluck(:search_text)
    @page_plain_text = block_search_texts.filter_map { |search_text| search_text.to_s.strip.presence }.join("\n")
    @page_word_count = @page_plain_text.scan(/\b[\p{L}\p{N}'-]+\b/u).size
    @recent_audit_events = policy_scope(AuditEvent)
                             .where(workspace_id: @workspace.id, auditable: @page)
                             .recent_first
                             .limit(10)
                             .to_a
    @page_versions = @page.versions.reorder(created_at: :desc).limit(10).to_a
  end

  def prepare_page_options_panel!
    @can_manage_permissions = policy(@page).permissions?
    @can_move_page = policy(@page).move_workspace?
    @memberships =
      if @can_manage_permissions
        policy_scope(Membership).where(workspace_id: @workspace.id).includes(:user).order(:created_at)
      else
        []
      end
    @move_workspace_options = @can_move_page ? move_workspace_options_for_page : []
    @shared_user_ids = @can_manage_permissions ? @page.page_shares.pluck(:user_id) : []
    @page_exports = policy_scope(PageExport).for_page(@page).recent_first.limit(10).to_a
    @page_templates = policy_scope(PageTemplate).for_workspace(@workspace).recent_first.limit(20).to_a
    @new_page_template = PageTemplate.new
    @share_links =
      if @can_manage_permissions
        policy_scope(ShareLink).for_page(@page).recent_first.to_a
      else
        []
      end
    @archived_blocks = policy_scope(Block).for_page(@page).archived.ordered.to_a
  end

  def move_target_workspace!
    workspace_id = params.require(:target_workspace_id)
    policy_scope(Workspace).where.not(id: @workspace.id).find(workspace_id)
  end

  def move_workspace_options_for_page
    policy_scope(Workspace)
      .where.not(id: @workspace.id)
      .order(:name)
      .select do |candidate_workspace|
        probe_record = Page.new(workspace: candidate_workspace, created_by: current_user, title: @page.title)
        policy(probe_record).create?
      end
  end
end
