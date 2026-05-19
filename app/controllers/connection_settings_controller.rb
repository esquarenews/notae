class ConnectionSettingsController < ApplicationController
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

    if clear_key_requested?
      persist_openai_api_key(nil, "OpenAI API key removed.")
      return
    end

    candidate_key = connection_setting_params[:openai_api_key].to_s.strip
    if candidate_key.blank?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: settings_flash_stream("alert", "Enter an OpenAI API key to save."),
                 status: :unprocessable_entity
        end
        format.html { redirect_to workspace_connection_settings_path(workspace_slug: @workspace.slug), alert: "Enter an OpenAI API key to save." }
      end
      return
    end

    persist_openai_api_key(candidate_key, "OpenAI API key saved.")
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_user
    @user = policy_scope(User).find(current_user.id)
  end

  def connection_setting_params
    params.fetch(:user, {}).permit(
      :openai_api_key,
      :clear_openai_api_key
    )
  end

  def clear_key_requested?
    connection_setting_params[:clear_openai_api_key].to_s == "1"
  end

  def persist_openai_api_key(value, success_notice)
    if @user.update(openai_api_key: value)
      render_connection_settings_response("notice", success_notice)
    else
      render_connection_settings_response("alert", @user.errors.full_messages.to_sentence, status: :unprocessable_entity)
    end
  end

  def render_connection_settings_response(type, message, status: :ok)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          settings_flash_stream(type, message),
          turbo_stream.replace("connection_settings_content", partial: "connection_settings/content")
        ], status: status
      end
      format.html do
        redirect_to workspace_connection_settings_path(workspace_slug: @workspace.slug), type => message
      end
    end
  end
end
