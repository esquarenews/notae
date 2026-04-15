class MeetingExtensionTokensController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def create
    authorize @workspace, :show?

    token = token_service.issue!

    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), flash: {
      notice: "Google Meet extension token created. Copy it into the extension now.",
      meeting_extension_token: token.token,
      meeting_extension_token_expires_at: token.expires_at&.iso8601
    }
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    authorize @workspace, :show?

    token_service.revoke!
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), notice: "Google Meet extension token revoked."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def token_service
    @token_service ||= Meetings::ExtensionTokenService.new(user: current_user, workspace: @workspace)
  end
end
