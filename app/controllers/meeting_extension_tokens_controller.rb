class MeetingExtensionTokensController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def create
    authorize @workspace, :show?

    token = token_service.issue!

    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), flash: {
      notice: "Google Meet extension token created. Copy it into the extension now.",
      meeting_extension_token_id: token.id
    }
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence
  rescue Meetings::ExtensionTokenService::UnavailableError,
         ActiveRecord::StatementInvalid,
         ActiveRecord::Encryption::Errors::Configuration,
         ActiveSupport::MessageEncryptor::InvalidMessage => error
    Rails.logger.error("[Meetings::ExtensionToken] create failed workspace=#{@workspace.slug} user=#{current_user.id}: #{error.class}: #{error.message}")
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: "Google Meet extension tokens are unavailable right now. Check server configuration and migrations."
  end

  def destroy
    authorize @workspace, :show?

    token_service.revoke!
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), notice: "Google Meet extension token revoked."
  rescue Meetings::ExtensionTokenService::UnavailableError,
         ActiveRecord::StatementInvalid,
         ActiveRecord::Encryption::Errors::Configuration,
         ActiveSupport::MessageEncryptor::InvalidMessage => error
    Rails.logger.error("[Meetings::ExtensionToken] revoke failed workspace=#{@workspace.slug} user=#{current_user.id}: #{error.class}: #{error.message}")
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: "Google Meet extension tokens are unavailable right now. Check server configuration and migrations."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def token_service
    @token_service ||= Meetings::ExtensionTokenService.new(user: current_user, workspace: @workspace)
  end
end
