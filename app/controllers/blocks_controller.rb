class BlocksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_page
  before_action :set_block, only: %i[update attach content download export_markdown panel reorder archive restore command]

  def create
    @block = @page.blocks.new(block_params)
    @block.created_by = current_user
    @block.workspace = @workspace
    authorize @block

    if @block.save
      insert_block_after_reference!(@block, params[:insert_after_id]) if params[:insert_after_id].present?
      respond_to do |format|
        format.turbo_stream { render turbo_stream: create_block_streams(@block, "Block created.") }
        format.html { redirect_to page_redirect_path, notice: "Block created." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: page_flash_stream("alert", @block.errors.full_messages.to_sentence),
                 status: :unprocessable_entity
        end
        format.html { redirect_to page_redirect_path, alert: @block.errors.full_messages.to_sentence }
      end
    end
  end

  def update
    source_block = source_block_for_update(@block)
    authorize source_block
    client_session_id = client_session_id_from_request

    if source_block.update(block_update_params)
      touched_blocks = sync_synced_group(source_block)
      touched_at = touch_pages_for_blocks!(touched_blocks)
      touched_blocks.each do |touched_block|
        broadcast_block_update(
          touched_block,
          page_updated_at: touched_at,
          client_session_id: client_session_id,
          origin_block_id: @block.id
        )
      end
      respond_to do |format|
        format.json { render json: serialized_block(@block.reload, page_updated_at: touched_at), status: :ok }
        format.html { redirect_to page_redirect_path, notice: "Block updated." }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: @block.errors.full_messages }, status: :unprocessable_entity }
        format.html { redirect_to page_redirect_path, alert: @block.errors.full_messages.to_sentence }
      end
    end
  end

  def attach
    authorize @block, :attach?
    TenantLimits::Enforcer.enforce!(workspace: @workspace, feature: :storage)
    file = params.dig(:block, :file)
    if file.present?
      Notae::UploadPolicy.validate_block_upload!(file, block_type: @block.block_type)
      @block.asset.attach(file)
      @block.touch
      touched_at = touch_pages_for_blocks!([ @block ])
      respond_to do |format|
        format.json do
          render json: {
            html: render_to_string(
              partial: "pages/block_media",
              formats: [ :html ],
              locals: {
                workspace: @workspace,
                page: @page,
                block: @block.reload,
                embedded_page_params: current_embedded_page_params
              }
            ),
            updated_at: @block.updated_at&.iso8601(6),
            page_updated_at: touched_at&.iso8601(6)
          }, status: :ok
        end
        format.html { redirect_to page_redirect_path, notice: "File uploaded." }
      end
    else
      render_attach_error("Please choose a file.")
    end
  rescue Notae::UploadPolicy::InvalidUpload => error
    render_attach_error(error.message)
  rescue TenantLimits::Enforcer::LimitExceeded => error
    render_attach_error(error.message)
  end

  def content
    authorize @block, :show?

    render json: serialized_block(@block), status: :ok
  end

  def download
    authorize @block, :download?
    unless @block.asset.attached?
      redirect_to page_redirect_path, alert: "No file attached."
      return
    end

    disposition =
      if params[:disposition] == "inline" && Notae::UploadPolicy.safe_inline_media_content_type?(@block.asset.content_type)
        "inline"
      else
        "attachment"
      end
    send_data @block.asset.download,
              filename: @block.asset.filename.to_s,
              type: @block.asset.content_type,
              disposition: disposition
  end

  def export_markdown
    authorize @block, :show?

    render plain: Blocks::MarkdownExportService.call(block: @block),
           content_type: "text/markdown; charset=utf-8"
  end

  def panel
    authorize @block, :show?
    return head :forbidden if @page.remove_blocks? || @page.locked? || embedded_page_shell?

    render partial: "pages/block_menu_body",
           locals: {
             workspace: @workspace,
             page: @page,
             block: @block,
             embedded_page_params: current_embedded_page_params
           }
  end

  def reorder
    authorize @block, :reorder?
    Blocks::ReorderService.call(
      block: @block,
      target_parent_id: params[:target_parent_id],
      target_index: params[:target_index]
    )
    respond_to do |format|
      format.json { head :ok }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "notae_doc_canvas",
          partial: "pages/document_canvas",
          locals: {
            workspace: @workspace,
            page: @page,
            blocks_by_parent: current_page_render_context[:blocks_by_parent],
            reader_mode: current_page_render_context[:reader_mode],
            embedded_page_params: current_embedded_page_params
          }
        )
      end
      format.html { redirect_to page_redirect_path(anchor: "block_#{@block.id}"), notice: "Block updated." }
    end
  end

  def archive
    authorize @block, :archive?
    Blocks::ArchiveService.call(block: @block)
    AuditEventLogger.log!(
      workspace: @workspace,
      actor: current_user,
      action: "delete",
      metadata: { kind: "block_archive", block_id: @block.id, page_id: @page.id },
      auditable: @block
    )
    redirect_to page_redirect_path, notice: "Block archived."
  end

  def restore
    authorize @block, :restore?
    Blocks::RestoreService.call(block: @block)
    redirect_to page_redirect_path, notice: "Block restored."
  end

  def command
    authorize @block, :command?

    target_page = nil
    if block_command_params[:target_page_id].present?
      target_page = policy_scope(Page).for_workspace(@workspace).find(block_command_params[:target_page_id])
    end

    target_database = nil
    if block_command_params[:target_database_id].present?
      target_database = policy_scope(Database).for_workspace(@workspace).active.find(block_command_params[:target_database_id])
    end

    result = Blocks::CommandService.call(
      block: @block,
      page: @page,
      workspace: @workspace,
      actor: current_user,
      command: block_command_params[:command],
      target: block_command_params[:target],
      color: block_command_params[:color],
      highlight: block_command_params[:highlight],
      target_page: target_page,
      target_database: target_database,
      note: block_command_params[:note]
    )

    touched_blocks = sync_synced_group(result[:synced_source_block])
    touched_blocks.each do |touched_block|
      broadcast_block_update(
        touched_block,
        client_session_id: client_session_id_from_request,
        origin_block_id: @block.id
      )
    end

    redirect_page_id = result[:redirect_page_id] || @page.id
    respond_to do |format|
      format.turbo_stream do
        if inline_block_command_response?(result)
          render turbo_stream: inline_block_command_streams(result, touched_blocks)
        else
          redirect_to page_redirect_path(
            redirect_page_id,
            anchor: result[:focus_anchor],
            split_page_id: result[:split_page_id],
            split_source: result[:split_source],
            clear_split: result[:clear_split]
          ), notice: result[:notice]
        end
      end
      format.html do
        redirect_to page_redirect_path(
          redirect_page_id,
          anchor: result[:focus_anchor],
          split_page_id: result[:split_page_id],
          split_source: result[:split_source],
          clear_split: result[:clear_split]
        ),
                    notice: result[:notice]
      end
    end
  rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid, ArgumentError => error
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "page_flash_messages",
          partial: "shared/flash_messages",
          locals: {
            flash_messages: [ [ "alert", error.message ] ],
            flash_dom_id: "page_flash_messages",
            flash_host_class: "notae-page-inline-flash-host"
          }
        ), status: :unprocessable_entity
      end
      format.html { redirect_to page_redirect_path, alert: error.message }
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_page
    @page = policy_scope(Page).for_workspace(@workspace).find(params[:page_id])
    authorize @page, :show?
  end

  def set_block
    @block = policy_scope(Block).for_page(@page).find(params[:id])
  end

  def render_attach_error(message)
    respond_to do |format|
      format.json { render json: { errors: [ message ] }, status: :unprocessable_entity }
      format.html { redirect_to page_redirect_path, alert: message }
    end
  end

  def block_params
    params.require(:block).permit(:parent_block_id, :block_type, content_json: {})
  end

  def block_update_params
    permitted = params.require(:block).permit(:block_type, :embed_url)
    if params[:block].key?(:content_json)
      raw_content = params[:block][:content_json]
      content_json = raw_content.respond_to?(:to_unsafe_h) ? raw_content.to_unsafe_h : raw_content
      formatted_content = DateMentions::Formatter.replace_in_content_json(
        content_json: content_json,
        preference: current_user.date_format_preference
      )
      permitted[:content_json] = preserved_block_metadata.merge(formatted_content)
    end
    permitted
  end

  def preserved_block_metadata
    return {} unless @block.content_json.is_a?(Hash)

    @block.content_json.each_with_object({}) do |(key, value), metadata|
      metadata[key] = value if key.to_s.start_with?("notae_")
    end
  end

  def block_command_params
    params.require(:block_command).permit(:command, :target, :color, :highlight, :target_page_id, :target_database_id, :note)
  end

  def broadcast_block_update(block, page_updated_at: nil, client_session_id: nil, origin_block_id: nil)
    return if block.page_id.blank?

    ActionCable.server.broadcast(
      "page:#{block.page_id}:collaboration",
      {
        type: "block_updated",
        actor_id: current_user.id,
        client_session_id: client_session_id,
        origin_block_id: origin_block_id,
        block: serialized_block(block, page_updated_at: page_updated_at)
      }
    )
  end

  def serialized_block(block, page_updated_at: nil)
    {
      id: block.id,
      block_type: block.block_type,
      content_json: block.content_json,
      updated_at: block.updated_at&.iso8601(6),
      page_updated_at: page_updated_at&.iso8601(6)
    }
  end

  def touch_pages_for_blocks!(blocks)
    page_ids = blocks.filter_map(&:page_id)
    page_ids << @page.id
    touched_at = Time.current
    Page.where(id: page_ids.uniq).update_all(updated_at: touched_at)
    touched_at
  end

  def source_block_for_update(block)
    source_id = block.synced_source_block_id
    return block if source_id.blank? || source_id.to_s == block.id.to_s

    policy_scope(Block).for_workspace(@workspace).find_by(id: source_id) || block
  end

  def client_session_id_from_request
    request.headers["X-Notae-Client-Session"].to_s.presence
  end

  def sync_synced_group(source_block)
    return [] if source_block.blank?

    sync_root =
      if source_block.synced_copy?
        policy_scope(Block).for_workspace(@workspace).find_by(id: source_block.synced_source_block_id) || source_block
      else
        source_block
      end

    return [ sync_root ] unless sync_root.id.present?

    copy_ids = policy_scope(Block)
               .for_workspace(@workspace)
               .active
               .where("content_json ->> 'notae_synced_source_id' = ?", sync_root.id.to_s)
               .pluck(:id)

    if copy_ids.any?
      payload = sync_root.content_json.deep_dup
      payload["notae_synced_source_id"] = sync_root.id.to_s
      now = Time.current
      Block.where(id: copy_ids).update_all(
        content_json: payload,
        block_type: sync_root.block_type,
        search_text: sync_root.search_text,
        updated_at: now
      )
    end

    Block.where(id: [ sync_root.id, *copy_ids ]).to_a
  end

  def page_redirect_path(page_id = @page.id, anchor: nil, split_page_id: nil, split_source: nil, clear_split: false)
    route_params = { workspace_slug: @workspace.slug, id: page_id }
    route_params[:embedded] = "1" if embedded_page_shell?
    route_params[:options_menu] = "open" if params[:options_menu].to_s == "open"
    unless clear_split
      route_params[:split_page_id] = split_page_id || params[:split_page_id].presence
      route_params[:split_source] = split_source || params[:split_source].presence
    end
    route_params[:anchor] = anchor if anchor.present?
    page_path(route_params)
  end

  def embedded_page_shell?
    params[:embedded].to_s == "1"
  end

  def current_embedded_page_params
    embedded_page_shell? ? { embedded: "1" } : {}
  end

  def inline_block_command_response?(result)
    return false unless request.format.turbo_stream?
    return false unless result[:redirect_page_id].blank? || result[:redirect_page_id] == @page.id

    case block_command_params[:command].to_s
    when "color", "highlight"
      true
    when "turn_into"
      !%w[page page_in synced_block].include?(block_command_params[:target].to_s)
    else
      false
    end
  end

  def inline_block_command_streams(result, touched_blocks)
    page_render_context = current_page_render_context
    streams = [
      page_flash_stream("notice", result[:notice] || "Block updated.")
    ]

    touched_blocks
      .select { |touched_block| touched_block.page_id == @page.id }
      .each do |touched_block|
        streams << turbo_stream.replace(
          "block_#{touched_block.id}",
          partial: "pages/block_item",
          locals: {
            workspace: @workspace,
            page: @page,
            block: page_render_context[:block_lookup].fetch(touched_block.id),
            blocks_by_parent: page_render_context[:blocks_by_parent],
            index: page_render_context[:indexes].fetch(touched_block.id, 0),
            reader_mode: page_render_context[:reader_mode],
            embedded_page_params: current_embedded_page_params
          }
        )
      end

    streams
  end

  def create_block_streams(block, notice)
    page_render_context = current_page_render_context
    [
      page_flash_stream("notice", notice),
      turbo_stream.append(
        block_tree_dom_id(block.parent_block_id),
        partial: "pages/block_item",
        locals: {
          workspace: @workspace,
          page: @page,
          block: page_render_context[:block_lookup].fetch(block.id),
          blocks_by_parent: page_render_context[:blocks_by_parent],
          index: sibling_index_for_render(page_render_context, block),
          reader_mode: page_render_context[:reader_mode],
          embedded_page_params: current_embedded_page_params
        }
      )
    ]
  end

  def insert_block_after_reference!(block, reference_block_id)
    reference = policy_scope(Block).for_page(@page).active.find_by(id: reference_block_id)
    return if reference.blank?

    siblings = policy_scope(Block).for_page(@page).active.where(parent_block_id: reference.parent_block_id).ordered.to_a
    reference_index = siblings.index { |candidate| candidate.id == reference.id }
    return if reference_index.nil?

    Blocks::ReorderService.call(
      block: block,
      target_parent_id: reference.parent_block_id,
      target_index: reference_index + 1
    )
  end

  def page_flash_stream(type, message)
    turbo_stream.replace(
      "page_flash_messages",
      partial: "shared/flash_messages",
      locals: {
        flash_messages: [ [ type, message ] ],
        flash_dom_id: "page_flash_messages",
        flash_host_class: "notae-page-inline-flash-host"
      }
    )
  end

  def sibling_index_for_render(page_render_context, block)
    Array(page_render_context[:blocks_by_parent][block.parent_block_id]).index { |candidate| candidate.id == block.id } || 0
  end

  def block_tree_dom_id(parent_id)
    parent_id.present? ? "notae_doc_tree_#{parent_id}" : "notae_doc_tree_root"
  end

  def current_page_render_context
    @current_page_render_context ||= begin
      render_context = Pages::RenderContextBuilder.new(
        page: @page,
        block_scope: policy_scope(Block)
      ).call
      {
        active_blocks: render_context.active_blocks,
        blocks_by_parent: render_context.blocks_by_parent,
        block_lookup: render_context.block_lookup,
        indexes: render_context.indexes,
        reader_mode: render_context.reader_mode
      }
    end
  end
end
