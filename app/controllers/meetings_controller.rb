class MeetingsController < ApplicationController
  include RequestPerformanceInstrumentation

  ACTIVE_RECORDING_STATUSES = %w[joining recording].freeze
  POLLING_STATUSES = %w[joining recording uploading processing summarizing proposing].freeze
  PROCESSING_COMPLETED_STATUSES = %w[uploading processing summarizing proposing completed failed cancelled].freeze
  SECTION_LIMIT = 20
  STATUS_STALE_CHECK_INTERVAL = 45.seconds
  STALE_HEARTBEAT_CUTOFF = 3.minutes

  before_action :authenticate_user!
  before_action :set_workspace
  track_request_performance_for :show, :status

  def show
    authorize @workspace, :show?
    load_meetings_dashboard_data!
    @meeting_session = MeetingSession.new(workspace: @workspace, capture_mode: "upload", provider: "local", status: "scheduled")
    @meeting_extension_token = nil
    @meeting_extension_token_expires_at = nil
    load_meeting_extension_feedback!
    load_meeting_extension_token_state!
    load_new_meeting_extension_token!
  end

  def status
    authorize @workspace, :show?
    load_meetings_dashboard_data!(status_only: true)

    render json: {
      html: render_to_string(
        partial: "meetings/sessions_sections",
        formats: [ :html ],
        locals: {
          workspace: @workspace,
          active_recording_sessions: @active_recording_sessions,
          scheduled_future_sessions: @scheduled_future_sessions,
          processing_completed_sessions: @processing_completed_sessions,
          show_speaker_mapping: false
        }
      ),
      active: @meetings_status_polling_active
    }
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def load_meetings_dashboard_data!(status_only: false)
    expire_stale_bot_runs!(status_only: status_only)

    unless status_only
      @upcoming_events = policy_scope(KalendariumEvent)
                           .for_workspace(@workspace)
                           .select(:id, :title, :starts_at_utc, :ends_at_utc, :metadata_json, :kalendarium_calendar_id)
                           .where("starts_at_utc >= ?", Time.current - 2.hours)
                           .where.not(status: "cancelled")
                           .where.not(metadata_json: {})
                           .order(:starts_at_utc)
                           .limit(30)
                           .to_a
                           .select { |event| event.meeting_join_url.present? }
    end

    load_session_sections!(status_only: status_only)

    unless status_only
      @pending_action_proposals = policy_scope(KalendariumWriteProposal)
                                    .for_workspace(@workspace)
                                    .pending
                                    .where(user_id: current_user.id)
                                    .where("payload_json ->> 'meeting_session_id' IS NOT NULL")
                                    .recent_first
                                    .limit(20)
                                    .to_a
    end
  end

  def load_session_sections!(status_only: false)
    now = Time.current
    scope = meeting_sessions_scope

    @active_recording_count = scope.where(capture_mode: %w[online_bot browser_extension in_person_mic], status: ACTIVE_RECORDING_STATUSES).count
    @scheduled_future_count = scope.joins(:kalendarium_event)
                                   .where(capture_mode: "online_bot", status: "scheduled")
                                   .where("kalendarium_events.starts_at_utc > ?", now)
                                   .count
    @processing_completed_count = scope.where(status: PROCESSING_COMPLETED_STATUSES).count
    @meetings_status_polling_active = scope.where(status: POLLING_STATUSES).exists?

    @active_recording_sessions = if @active_recording_count.positive?
      scope.where(capture_mode: %w[online_bot browser_extension in_person_mic], status: ACTIVE_RECORDING_STATUSES)
           .includes(:kalendarium_event, :page, :latest_meeting_bot_run)
           .recent_first
           .limit(SECTION_LIMIT)
           .to_a
    else
      []
    end

    @scheduled_future_sessions = if @scheduled_future_count.positive?
      scope.joins(:kalendarium_event)
           .where(capture_mode: "online_bot", status: "scheduled")
           .where("kalendarium_events.starts_at_utc > ?", now)
           .includes(:kalendarium_event, :page, :latest_meeting_bot_run)
           .recent_first
           .limit(SECTION_LIMIT)
           .to_a
    else
      []
    end

    processing_includes = [ :kalendarium_event, :page, :latest_meeting_bot_run ]
    processing_includes << :meeting_utterances unless status_only

    @processing_completed_sessions = if @processing_completed_count.positive?
      scope.where(status: PROCESSING_COMPLETED_STATUSES)
           .includes(*processing_includes)
           .recent_first
           .limit(SECTION_LIMIT)
           .to_a
    else
      []
    end
  end

  def meeting_sessions_scope
    @meeting_sessions_scope ||= policy_scope(MeetingSession).for_workspace(@workspace)
  end

  def expire_stale_bot_runs!(status_only: false)
    if status_only
      last_status_check = Rails.cache.read(status_stale_check_cache_key)
      return if last_status_check.present? && last_status_check > STATUS_STALE_CHECK_INTERVAL.ago
    end

    stale_cutoff = STALE_HEARTBEAT_CUTOFF.ago
    runs_scope = MeetingBotRun.joins(:meeting_session).where(meeting_sessions: { workspace_id: @workspace.id })

    stale_with_heartbeat = runs_scope.where(status: %w[claimed joining recording uploading])
                                     .where("last_heartbeat_at IS NOT NULL AND last_heartbeat_at < ?", stale_cutoff)
    stale_unclaimed = runs_scope.where(status: %w[queued joining])
                                .where(last_heartbeat_at: nil)
                                .where("meeting_bot_runs.created_at < ?", stale_cutoff)

    stale_run_ids = stale_with_heartbeat.or(stale_unclaimed).pluck(:id)
    return if stale_run_ids.empty?

    runs = MeetingBotRun.includes(:meeting_session).where(id: stale_run_ids)
    runs.find_each do |run|
      next if run.status == "failed"

      error_message = run.last_heartbeat_at.present? ? "Worker heartbeat timed out." : "Worker did not claim run."
      run.update!(
        status: "failed",
        finished_at: Time.current,
        error_message: error_message
      )
      session = run.meeting_session
      next if session.blank? || session.failed? || session.completed? || session.status == "cancelled"

      session.update!(
        status: "failed",
        error_message: "Meeting bot worker timed out.",
        ended_at: Time.current
      )
    end
  ensure
    Rails.cache.write(status_stale_check_cache_key, Time.current) if status_only
  end

  def status_stale_check_cache_key
    "meetings/#{@workspace.id}/status_stale_check"
  end

  def load_meeting_extension_token_state!
    token_service = meeting_extension_token_service
    @meeting_extension_tokens_available = token_service.storage_available?
    @active_meeting_extension_token = @meeting_extension_tokens_available ? token_service.latest_active_token : nil
  rescue Meetings::ExtensionTokenService::UnavailableError,
         ActiveRecord::StatementInvalid,
         ActiveRecord::Encryption::Errors::Configuration,
         ActiveSupport::MessageEncryptor::InvalidMessage => error
    Rails.logger.error("[Meetings::ExtensionToken] load failed workspace=#{@workspace.slug} user=#{current_user.id}: #{error.class}: #{error.message}")
    @meeting_extension_tokens_available = false
    @active_meeting_extension_token = nil
  end

  def load_new_meeting_extension_token!
    token_ref = params[:extension_token_ref].to_s.presence
    return if token_ref.blank? || params[:extension_token_status].to_s != "created" || !@meeting_extension_tokens_available

    token = meeting_extension_token_service.find_active_token_by_reference(token_ref)
    return if token.blank?

    @meeting_extension_token = token.token
    @meeting_extension_token_expires_at = token.expires_at
  rescue Meetings::ExtensionTokenService::UnavailableError,
         ActiveRecord::StatementInvalid,
         ActiveRecord::Encryption::Errors::Configuration,
         ActiveSupport::MessageEncryptor::InvalidMessage => error
    Rails.logger.error("[Meetings::ExtensionToken] reveal failed workspace=#{@workspace.slug} user=#{current_user.id}: #{error.class}: #{error.message}")
    @meeting_extension_token = nil
    @meeting_extension_token_expires_at = nil
  end

  def load_meeting_extension_feedback!
    case params[:extension_token_status].to_s
    when "created"
      @meeting_extension_feedback_type = :notice
      @meeting_extension_feedback_message = "Google Meet extension token created. Copy it into the extension now."
    when "revoked"
      @meeting_extension_feedback_type = :notice
      @meeting_extension_feedback_message = "Google Meet extension token revoked."
    when "unavailable"
      @meeting_extension_feedback_type = :alert
      @meeting_extension_feedback_message = "Google Meet extension tokens are unavailable right now. Check server configuration and migrations."
    when "invalid"
      @meeting_extension_feedback_type = :alert
      @meeting_extension_feedback_message = "Google Meet extension token could not be created. Please try again."
    end
  end

  def meeting_extension_token_service
    @meeting_extension_token_service ||= Meetings::ExtensionTokenService.new(user: current_user, workspace: @workspace)
  end
end
