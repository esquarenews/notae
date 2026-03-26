class BlocksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_page
  before_action :set_block, only: %i[update attach download reorder archive restore command]

  def create
    @block = @page.blocks.new(block_params)
    @block.created_by = current_user
    @block.workspace = @workspace
    authorize @block

    if @block.save
      redirect_to page_redirect_path, notice: "Block created."
    else
      redirect_to page_redirect_path, alert: @block.errors.full_messages.to_sentence
    end
  end

  def update
    source_block = source_block_for_update(@block)
    authorize source_block

    if source_block.update(block_update_params)
      touched_blocks = sync_synced_group(source_block)
      touched_at = touch_pages_for_blocks!(touched_blocks)
      touched_blocks.each { |touched_block| broadcast_block_update(touched_block) }
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
    file = params.dig(:block, :file)
    if file.present?
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
      respond_to do |format|
        format.json { render json: { errors: [ "Please choose a file." ] }, status: :unprocessable_entity }
        format.html { redirect_to page_redirect_path, alert: "Please choose a file." }
      end
    end
  end

  def download
    authorize @block, :download?
    unless @block.asset.attached?
      redirect_to page_redirect_path, alert: "No file attached."
      return
    end

    disposition = params[:disposition] == "inline" ? "inline" : "attachment"
    send_data @block.asset.download,
              filename: @block.asset.filename.to_s,
              type: @block.asset.content_type,
              disposition: disposition
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
            move_target_pages: current_page_render_context[:move_target_pages],
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
      note: block_command_params[:note]
    )

    touched_blocks = sync_synced_group(result[:synced_source_block])
    touched_blocks.each { |touched_block| broadcast_block_update(touched_block) }

    redirect_page_id = result[:redirect_page_id] || @page.id
    respond_to do |format|
      format.turbo_stream do
        if inline_block_command_response?(result)
          render turbo_stream: inline_block_command_streams(result, touched_blocks)
        else
          redirect_to page_redirect_path(redirect_page_id, anchor: result[:focus_anchor]), notice: result[:notice]
        end
      end
      format.html do
        redirect_to page_redirect_path(redirect_page_id, anchor: result[:focus_anchor]),
                    notice: result[:notice]
      end
    end
  rescue ActionController::ParameterMissing, ActiveRecord::RecordInvalid, ArgumentError => error
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "notae_flash_messages",
          partial: "shared/flash_messages",
          locals: { flash_messages: [ [ "alert", error.message ] ] }
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

  def block_params
    params.require(:block).permit(:parent_block_id, :block_type)
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
    params.require(:block_command).permit(:command, :target, :color, :highlight, :target_page_id, :note)
  end

  def broadcast_block_update(block)
    ActionCable.server.broadcast(
      "page:#{@page.id}:collaboration",
      {
        type: "block_updated",
        actor_id: current_user.id,
        block: serialized_block(block)
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

  def page_redirect_path(page_id = @page.id, anchor: nil)
    route_params = { workspace_slug: @workspace.slug, id: page_id }
    route_params[:embedded] = "1" if embedded_page_shell?
    route_params[:options_menu] = "open" if params[:options_menu].to_s == "open"
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
      turbo_stream.replace(
        "notae_flash_messages",
        partial: "shared/flash_messages",
        locals: { flash_messages: [ [ "notice", result[:notice] || "Block updated." ] ] }
      )
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
            all_pages: page_render_context[:move_target_pages],
            index: page_render_context[:indexes].fetch(touched_block.id, 0),
            reader_mode: page_render_context[:reader_mode],
            embedded_page_params: current_embedded_page_params
          }
        )
      end

    streams
  end

  def current_page_render_context
    @current_page_render_context ||= begin
      active_blocks = policy_scope(Block).for_page(@page).active.ordered.to_a
      {
        blocks_by_parent: active_blocks.group_by(&:parent_block_id),
        block_lookup: active_blocks.index_by(&:id),
        indexes: active_blocks.each_with_index.to_h { |block, index| [ block.id, index ] },
        move_target_pages: policy_scope(Page).for_workspace(@workspace).active.order(:created_at).to_a.reject { |candidate| candidate.id == @page.id },
        reader_mode: @page.remove_blocks? || @page.locked?
      }
    end
  end
end
