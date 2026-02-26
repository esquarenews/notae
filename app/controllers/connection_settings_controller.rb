class ConnectionSettingsController < ApplicationController
  SMTP_ATTRIBUTE_KEYS = %i[
    smtp_address
    smtp_port
    smtp_domain
    smtp_username
    smtp_password
    smtp_authentication
    smtp_enable_starttls_auto
    smtp_from_name
    smtp_from_email
  ].freeze

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

    if clear_smtp_settings_requested?
      persist_smtp_settings!(clear: true)
      return
    end

    if smtp_settings_submitted?
      persist_smtp_settings!(clear: false)
      return
    end

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
    params.fetch(:user, {}).permit(
      :openai_api_key,
      :clear_openai_api_key,
      :clear_smtp_settings,
      *SMTP_ATTRIBUTE_KEYS
    )
  end

  def clear_key_requested?
    connection_setting_params[:clear_openai_api_key].to_s == "1"
  end

  def clear_smtp_settings_requested?
    connection_setting_params[:clear_smtp_settings].to_s == "1"
  end

  def smtp_settings_submitted?
    (connection_setting_params.keys.map(&:to_sym) & SMTP_ATTRIBUTE_KEYS).any?
  end

  def persist_openai_api_key(value, success_notice)
    if @user.update(openai_api_key: value)
      redirect_to workspace_connection_settings_path(workspace_slug: @workspace.slug), notice: success_notice
    else
      redirect_to workspace_connection_settings_path(workspace_slug: @workspace.slug), alert: @user.errors.full_messages.to_sentence
    end
  end

  def persist_smtp_settings!(clear:)
    attributes =
      if clear
        {
          smtp_address: nil,
          smtp_port: nil,
          smtp_domain: nil,
          smtp_username: nil,
          smtp_password: nil,
          smtp_authentication: "plain",
          smtp_enable_starttls_auto: true,
          smtp_from_name: nil,
          smtp_from_email: nil
        }
      else
        smtp_connection_params.to_h
      end

    if @user.update(attributes)
      message = clear ? "Email SMTP settings removed." : "Email SMTP settings saved."
      redirect_to workspace_connection_settings_path(workspace_slug: @workspace.slug), notice: message
    else
      redirect_to workspace_connection_settings_path(workspace_slug: @workspace.slug), alert: @user.errors.full_messages.to_sentence
    end
  end

  def smtp_connection_params
    params_hash = connection_setting_params.slice(*SMTP_ATTRIBUTE_KEYS).to_h
    params_hash.transform_values! { |value| value.is_a?(String) ? value.strip : value }
    params_hash[:smtp_address] = params_hash[:smtp_address].presence
    params_hash[:smtp_domain] = params_hash[:smtp_domain].presence
    params_hash[:smtp_username] = params_hash[:smtp_username].presence
    params_hash[:smtp_from_name] = params_hash[:smtp_from_name].presence
    params_hash[:smtp_from_email] = params_hash[:smtp_from_email].presence
    params_hash[:smtp_authentication] = params_hash[:smtp_authentication].presence || "plain"
    params_hash[:smtp_enable_starttls_auto] = ActiveModel::Type::Boolean.new.cast(params_hash[:smtp_enable_starttls_auto])

    raw_port = params_hash[:smtp_port].to_s
    params_hash[:smtp_port] = raw_port.present? ? raw_port.to_i : nil

    if params_hash[:smtp_password].to_s.blank?
      params_hash.delete(:smtp_password)
    else
      params_hash[:smtp_password] = params_hash[:smtp_password].to_s
    end

    params_hash
  end
end
