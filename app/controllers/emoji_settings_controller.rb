class EmojiSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_custom_emoji, only: :destroy

  def show
    authorize @workspace, :show?
    load_custom_emojis
  end

  def create
    authorize @workspace, :update?

    upload = params.fetch(:workspace_emoji, {}).permit(:image)[:image]
    if upload.blank?
      load_custom_emojis
      flash.now[:alert] = "Choose an emoji image to upload."
      return render :show, status: :unprocessable_entity
    end

    @workspace_emoji = @workspace.custom_emojis.build
    @workspace_emoji.image.attach(upload)

    if @workspace_emoji.save
      redirect_to workspace_emoji_settings_path(workspace_slug: @workspace.slug), notice: "Custom emoji added."
    else
      load_custom_emojis
      flash.now[:alert] = @workspace_emoji.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
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
end
