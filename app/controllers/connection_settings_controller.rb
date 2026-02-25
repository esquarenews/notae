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
      redirect_to workspace_connection_settings_path(workspace_slug: @workspace.slug), alert: "Enter an OpenAI API key to save."
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
    params.fetch(:user, {}).permit(:openai_api_key, :clear_openai_api_key)
  end

  def clear_key_requested?
    connection_setting_params[:clear_openai_api_key].to_s == "1"
  end

  def persist_openai_api_key(value, success_notice)
    if @user.update(openai_api_key: value)
      redirect_to workspace_connection_settings_path(workspace_slug: @workspace.slug), notice: success_notice
    else
      redirect_to workspace_connection_settings_path(workspace_slug: @workspace.slug), alert: @user.errors.full_messages.to_sentence
    end
  end
end
