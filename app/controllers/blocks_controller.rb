class BlocksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_page
  before_action :set_block, only: %i[update attach download reorder archive restore]

  def create
    @block = @page.blocks.new(block_params)
    @block.created_by = current_user
    @block.workspace = @workspace
    authorize @block

    if @block.save
      redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Block created."
    else
      redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), alert: @block.errors.full_messages.to_sentence
    end
  end

  def update
    authorize @block

    if @block.update(block_update_params)
      respond_to do |format|
        format.json { render json: { id: @block.id, block_type: @block.block_type }, status: :ok }
        format.html { redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Block updated." }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: @block.errors.full_messages }, status: :unprocessable_entity }
        format.html { redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), alert: @block.errors.full_messages.to_sentence }
      end
    end
  end

  def attach
    authorize @block, :attach?
    file = params.dig(:block, :file)
    if file.present?
      @block.asset.attach(file)
      redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "File uploaded."
    else
      redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), alert: "Please choose a file."
    end
  end

  def download
    authorize @block, :download?
    unless @block.asset.attached?
      redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), alert: "No file attached."
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
    head :ok
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
    redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Block archived."
  end

  def restore
    authorize @block, :restore?
    Blocks::RestoreService.call(block: @block)
    redirect_to page_path(workspace_slug: @workspace.slug, id: @page.id), notice: "Block restored."
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
      permitted[:content_json] = raw_content.respond_to?(:to_unsafe_h) ? raw_content.to_unsafe_h : raw_content
    end
    permitted
  end
end
