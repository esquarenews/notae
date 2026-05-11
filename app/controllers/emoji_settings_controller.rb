class EmojiSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_custom_emoji, only: :destroy

  def show
    authorize @workspace, :show?
    @workspace_emoji = @workspace.custom_emojis.build
    @highlight_emoji_id = params[:highlight_emoji].presence
    load_custom_emojis
  end

  def create
    authorize @workspace, :update?

    emoji_params = params.fetch(:workspace_emoji, {}).permit(:image, :name)
    upload = emoji_params[:image]
    if upload.blank?
      @workspace_emoji = @workspace.custom_emojis.build(name: emoji_params[:name])
      return render_upload_error("Choose an emoji image to upload.")
    end

    @workspace_emoji = @workspace.custom_emojis.build(name: emoji_params[:name])
    Notae::UploadPolicy.validate_emoji_image!(upload)
    @workspace_emoji.image.attach(upload)

    if @workspace_emoji.save
      redirect_to workspace_emoji_settings_path(workspace_slug: @workspace.slug, highlight_emoji: @workspace_emoji.id),
                  notice: "#{@workspace_emoji.display_name} is ready to use in the emoji picker."
    else
      render_upload_error(@workspace_emoji.errors.full_messages.to_sentence)
    end
  rescue Notae::UploadPolicy::InvalidUpload => error
    @workspace_emoji ||= @workspace.custom_emojis.build(name: emoji_params[:name])
    render_upload_error(error.message)
  end

  def destroy
    authorize @workspace, :update?

    @workspace_emoji.destroy
    redirect_to workspace_emoji_settings_path(workspace_slug: @workspace.slug), notice: "Custom emoji removed."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_custom_emoji
    @workspace_emoji = @workspace.custom_emojis.find(params[:id])
  end

  def load_custom_emojis
    @custom_emojis = @workspace.custom_emojis.ordered.with_attached_image.to_a
  end

  def render_upload_error(message)
    @highlight_emoji_id = nil
    load_custom_emojis
    flash.now[:alert] = message
    render :show, status: :unprocessable_entity
  end
end
