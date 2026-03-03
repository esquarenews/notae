class MeetingSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_meeting_session, only: %i[update start stop reprocess speakers]

  def create
    event = find_selected_event
    authorize MeetingSession.new(
      workspace: @workspace,
      created_by: current_user,
      updated_by: current_user,
      title: meeting_session_params[:title],
      capture_mode: normalized_capture_mode,
      provider: normalized_provider,
      status: "scheduled"
    )

    session = Meetings::SessionLifecycleService.new(workspace: @workspace, actor: current_user).create_session!(
      title: meeting_session_params[:title],
      capture_mode: normalized_capture_mode,
      provider: normalized_provider,
      kalendarium_event: event,
      join_url: meeting_session_params[:join_url],
      consent_warning_acknowledged: ActiveModel::Type::Boolean.new.cast(meeting_session_params[:consent_warning_acknowledged]),
      force_new: ActiveModel::Type::Boolean.new.cast(meeting_session_params[:force_new])
    )
    attach_capture_files!(session)
    handle_session_dispatch!(session)

    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), notice: "Meeting session created."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence
  rescue StandardError => error
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: error.message
  end

  def update
    authorize @meeting_session
    event = if meeting_session_params.key?(:kalendarium_event_id)
      find_selected_event
    else
      @meeting_session.kalendarium_event
    end

    @meeting_session.assign_attributes(
      title: meeting_session_params[:title].to_s.strip.presence || @meeting_session.title,
      join_url: normalized_join_url(meeting_session_params[:join_url]) || @meeting_session.join_url,
      kalendarium_event: event,
      updated_by: current_user
    )
    attach_capture_files!(@meeting_session)
    @meeting_session.save!

    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), notice: "Meeting session updated."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence
  end

  def start
    authorize @meeting_session

    @meeting_session.update!(status: "recording", started_at: Time.current, updated_by: current_user) unless @meeting_session.status == "recording"
    handle_session_dispatch!(@meeting_session)
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), notice: "Meeting capture started."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence
  end

  def stop
    authorize @meeting_session

    if @meeting_session.capture_files.attached?
      @meeting_session.update!(status: "uploading", ended_at: Time.current, updated_by: current_user)
      Meetings::ProcessSessionJob.perform_later(@meeting_session.id)
      notice = "Meeting capture uploaded for processing."
    else
      @meeting_session.update!(status: "cancelled", ended_at: Time.current, updated_by: current_user)
      notice = "Meeting capture stopped."
    end

    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), notice: notice
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence
  end

  def reprocess
    authorize @meeting_session

    if @meeting_session.capture_files.attached?
      @meeting_session.update!(status: "processing", error_message: nil, updated_by: current_user)
      Meetings::ProcessSessionJob.perform_later(@meeting_session.id)
      notice = "Reprocessing queued."
    elsif @meeting_session.transcript_text.to_s.strip.present?
      @meeting_session.update!(status: "summarizing", error_message: nil, updated_by: current_user)
      Meetings::SummarizeSessionJob.perform_later(@meeting_session.id)
      notice = "Summary regeneration queued."
    else
      redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: "No capture file or transcript is available to reprocess."
      return
    end

    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), notice: notice
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence
  end

  def speakers
    authorize @meeting_session
    mapping = speaker_map_params

    Meetings::SpeakerResolutionService.new(session: @meeting_session).apply_manual_mapping!(mapping)
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), notice: "Speaker names updated."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_meeting_session
    @meeting_session = policy_scope(MeetingSession).for_workspace(@workspace).find(params[:id])
  end

  def meeting_session_params
    params.require(:meeting_session).permit(
      :title,
      :capture_mode,
      :provider,
      :join_url,
      :kalendarium_event_id,
      :consent_warning_acknowledged,
      :force_new,
      capture_files: []
    )
  end

  def speaker_map_params
    params.fetch(:meeting_session, ActionController::Parameters.new)
          .permit(speaker_map: {})
          .fetch(:speaker_map, {})
  end

  def find_selected_event
    event_id = meeting_session_params[:kalendarium_event_id].to_s.strip
    return nil if event_id.blank?

    policy_scope(KalendariumEvent).for_workspace(@workspace).find(event_id)
  end

  def normalized_capture_mode
    value = meeting_session_params[:capture_mode].to_s
    MeetingSession::CAPTURE_MODES.include?(value) ? value : "upload"
  end

  def normalized_provider
    value = meeting_session_params[:provider].to_s
    MeetingSession::PROVIDERS.include?(value) ? value : "local"
  end

  def normalized_join_url(raw_url)
    value = raw_url.to_s.strip
    return nil if value.blank?
    return value if value.start_with?("https://", "http://")

    nil
  end

  def attach_capture_files!(session)
    files = Array(meeting_session_params[:capture_files]).reject(&:blank?)
    return if files.empty?

    session.capture_files.attach(files)
  end

  def handle_session_dispatch!(session)
    if session.capture_mode == "online_bot"
      Meetings::BotDispatchService.new(session: session, actor: current_user).dispatch!
      return
    end

    return unless session.capture_files.attached?

    session.update!(status: "uploading", updated_by: current_user)
    Meetings::ProcessSessionJob.perform_later(session.id)
  end
end
