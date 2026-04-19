class AccountSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user

  def show
    authorize @workspace, :show?
    authorize @user, :update?
  end

  def update
    authorize @workspace, :show?
    authorize @user, :update?

    attachment_payload = avatar_attachment_payload
    remove_avatar = remove_avatar_requested?
    profile_params = account_params.except(:avatar)

    ActiveRecord::Base.transaction do
      @user.update!(profile_params)
      @user.avatar.purge if remove_avatar && @user.avatar.attached?
      @user.avatar.attach(
        io: attachment_payload[:io],
        filename: attachment_payload[:filename],
        content_type: attachment_payload[:content_type]
      ) if attachment_payload.present?
    end

    render_account_settings_response("notice", "Account settings updated.", replace_content: true)
  rescue ActiveRecord::RecordInvalid => error
    render_account_settings_response(
      "alert",
      error.record.errors.full_messages.to_sentence,
      status: :unprocessable_entity
    )
  rescue Users::AvatarUploadProcessor::Error => error
    render_account_settings_response("alert", error.message, status: :unprocessable_entity)
  ensure
    Users::AvatarUploadProcessor.close(attachment_payload)
  end

  def request_deletion
    authorize @workspace, :show?
    authorize @user, :update?

    @user.account_deletion_recipients.each do |recipient|
      AccountSettingsMailer.with(user: @user, workspace: @workspace, recipient: recipient).account_deletion_requested.deliver_now
    end

    render_account_settings_response(
      "notice",
      "Account deletion confirmation sent to #{helpers.to_sentence(@user.account_deletion_recipients)}."
    )
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_user
    @user = policy_scope(User).find(current_user.id)
  end

  def account_params
    params.fetch(:user, {}).permit(:avatar, :full_name, :backup_email, :personal_bio)
  end

  def avatar_attachment_payload
    upload = account_params[:avatar]
    return nil if upload.blank?

    Users::AvatarUploadProcessor.new(upload: upload).call
  end

  def remove_avatar_requested?
    ActiveModel::Type::Boolean.new.cast(params.dig(:user, :remove_avatar))
  end

  def render_account_settings_response(type, message, status: :ok, replace_content: false)
    respond_to do |format|
      format.turbo_stream do
        streams = [ settings_flash_stream(type, message) ]
        if replace_content
          streams << turbo_stream.replace("account_settings_content", partial: "account_settings/content")
        end

        render turbo_stream: streams, status: status
      end
      format.html do
        redirect_to workspace_account_settings_path(workspace_slug: @workspace.slug), type => message
      end
    end
  end
end
