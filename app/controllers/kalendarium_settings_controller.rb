class KalendariumSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    @connections = policy_scope(KalendariumConnection).for_workspace(@workspace).includes(:kalendarium_calendars).order(created_at: :desc)
    @external_connections = resolve_external_connections
    @calendars = policy_scope(KalendariumCalendar).for_workspace(@workspace).order(:name)
    @time_zone_options = User.time_zone_options
    @google_oauth_configured = Kalendarium::GoogleOauthService.configured?
    @google_oauth_debug = google_oauth_debug_state if Rails.env.development?
  end

  def update
    authorize @workspace, :show?
    authorize current_user, :update?

    time_zones = Array(settings_params[:calendar_extra_time_zones]).map(&:to_s).reject(&:blank?).uniq
    if current_user.update(calendar_extra_time_zones: time_zones)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: settings_flash_stream("notice", "Kalendarium settings updated.") }
        format.html { redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), notice: "Kalendarium settings updated." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: settings_flash_stream("alert", current_user.errors.full_messages.to_sentence),
                 status: :unprocessable_entity
        end
        format.html { redirect_to workspace_kalendarium_settings_path(workspace_slug: @workspace.slug), alert: current_user.errors.full_messages.to_sentence }
      end
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def settings_params
    params.fetch(:user, {}).permit(calendar_extra_time_zones: [])
  end

  def google_oauth_debug_state
    credentials = Rails.application.credentials

    {
      env: Rails.env,
      env_client_id_present: (
        ENV["GOOGLE_OAUTH_CLIENT_ID"].to_s.strip.present? ||
        ENV["GOOGLE_CLIENT_ID"].to_s.strip.present?
      ),
      env_client_secret_present: (
        ENV["GOOGLE_OAUTH_CLIENT_SECRET"].to_s.strip.present? ||
        ENV["GOOGLE_CLIENT_SECRET"].to_s.strip.present?
      ),
      credentials_client_id_present: credentials_value_present?(
        credentials,
        %i[google oauth_client_id],
        %i[google_oauth client_id],
        %i[google_oauth_client_id],
        [ "GOOGLE_OAUTH_CLIENT_ID" ]
      ),
      credentials_client_secret_present: credentials_value_present?(
        credentials,
        %i[google oauth_client_secret],
        %i[google_oauth client_secret],
        %i[google_oauth_client_secret],
        [ "GOOGLE_OAUTH_CLIENT_SECRET" ]
      ),
      credentials_path: Rails.application.config.credentials.content_path.to_s
    }
  rescue StandardError
    nil
  end

  def credentials_value_present?(credentials, *paths)
    paths.any? do |path|
      candidate = Array(path)
      variants = [
        candidate,
        candidate.map { |segment| segment.respond_to?(:to_sym) ? segment.to_sym : segment },
        candidate.map(&:to_s)
      ].uniq

      variants.any? do |variant|
        value = if variant.length == 1
          credentials[variant.first]
        else
          credentials.dig(*variant)
        end
        value.to_s.strip.present?
      end
    end
  end

  def resolve_external_connections
    local_signatures = @connections.map { |connection| connection_signature(connection) }.to_set

    policy_scope(KalendariumConnection)
      .where.not(workspace_id: @workspace.id)
      .includes(:workspace)
      .order(:label, :created_at)
      .reject { |connection| local_signatures.include?(connection_signature(connection)) }
  end

  def connection_signature(connection)
    [
      connection.provider.to_s,
      connection.label.to_s,
      connection.shared_connection? ? "workspace" : "user"
    ]
  end
end
