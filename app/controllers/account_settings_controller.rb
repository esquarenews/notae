class AccountSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user
  before_action :load_api_token_settings
  before_action :set_api_token, only: %i[revoke_api_token rotate_api_token]

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

  def create_api_token
    authorize @workspace, :show?
    authorize @user, :update?

    lifecycle_service = ApiTokens::LifecycleService.new(user: @user, workspace: @workspace)
    @issued_api_token = lifecycle_service.issue!(
      name: api_token_params[:name],
      scopes_json: api_token_params[:scopes_json],
      expires_at: api_token_params[:expires_at],
      metadata: { source: "account_settings" }
    )
    @issued_api_token_value = @issued_api_token.token

    load_api_token_settings
    render_account_settings_response(
      "notice",
      "API token created. Copy it now because it will not be shown again.",
      replace_content: true,
      render_html: true
    )
  rescue ActiveRecord::RecordInvalid => error
    @new_api_token = error.record
    load_api_token_settings
    render_account_settings_response(
      "alert",
      error.record.errors.full_messages.to_sentence,
      status: :unprocessable_entity,
      replace_content: true,
      render_html: true
    )
  end

  def revoke_api_token
    authorize @workspace, :show?
    authorize @user, :update?

    ApiTokens::LifecycleService.new(user: @user, workspace: @workspace).revoke!(
      @api_token,
      metadata: { source: "account_settings" }
    )
    load_api_token_settings

    render_account_settings_response(
      "notice",
      "API token revoked.",
      replace_content: true,
      render_html: true
    )
  end

  def rotate_api_token
    authorize @workspace, :show?
    authorize @user, :update?

    @issued_api_token = ApiTokens::LifecycleService.new(user: @user, workspace: @workspace).rotate!(
      @api_token,
      metadata: { source: "account_settings" }
    )
    @issued_api_token_value = @issued_api_token.token
    load_api_token_settings

    render_account_settings_response(
      "notice",
      "API token rotated. Copy the replacement now because it will not be shown again.",
      replace_content: true,
      render_html: true
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

  def api_token_params
    params.fetch(:api_token, {}).permit(:name, :expires_at, scopes_json: [])
  end

  def avatar_attachment_payload
    upload = account_params[:avatar]
    return nil if upload.blank?

    Users::AvatarUploadProcessor.new(upload: upload).call
  end

  def remove_avatar_requested?
    ActiveModel::Type::Boolean.new.cast(params.dig(:user, :remove_avatar))
  end

  def set_api_token
    @api_token = @user.api_tokens.find(params[:id])
  end

  def load_api_token_settings
    @api_tokens = @user.api_tokens.order(created_at: :desc).limit(12).to_a
    @api_token_audit_events = ApiTokenAuditEvent
      .where(user: @user)
      .includes(:workspace, :api_token)
      .recent_first
      .limit(12)
      .to_a
    @new_api_token ||= @user.api_tokens.new(scopes_json: [ ApiToken::SCOPE_ALL ])
  end

  def render_account_settings_response(type, message, status: :ok, replace_content: false, render_html: false)
    respond_to do |format|
      format.turbo_stream do
        streams = [ settings_flash_stream(type, message) ]
        if replace_content
          streams << turbo_stream.replace("account_settings_content", partial: "account_settings/content")
        end

        render turbo_stream: streams, status: status
      end
      format.html do
        if render_html
          flash.now[type] = message
          render :show, status: status
        else
          redirect_to workspace_account_settings_path(workspace_slug: @workspace.slug), type => message
        end
      end
    end
  end
end
