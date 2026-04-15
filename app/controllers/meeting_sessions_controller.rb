class MeetingSessionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_meeting_session, only: %i[update start stop reprocess speakers]

  def create
    if normalized_capture_mode == "online_bot"
      authorize MeetingSession.new(
        workspace: @workspace,
        created_by: current_user,
        updated_by: current_user,
        title: meeting_session_params[:title],
        capture_mode: normalized_capture_mode,
        provider: normalized_provider,
        status: "scheduled"
      )
      redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: "Scheduled browser capture has been retired. Use the Google Meet transcript extension instead."
      return
    end

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
    dispatch_result = handle_session_dispatch!(session)
    notice = if dispatch_result == :deferred
      "Meeting session scheduled. Capture will start at meeting time."
    else
      "Meeting session created."
    end

    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), notice: notice
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
    schedule_online_session_jobs!(@meeting_session)

    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), notice: "Meeting session updated."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: error.record.errors.full_messages.to_sentence
  end

  def start
    authorize @meeting_session
    redirect_to workspace_meetings_path(workspace_slug: @workspace.slug), alert: "Scheduled browser capture has been retired. Use the Google Meet transcript extension instead."
  end

  def stop
    authorize @meeting_session
    result = Meetings::StopSessionService.new(
      session: @meeting_session,
      actor: current_user,
      reason: "Stopped by user."
    ).call
    notice = result == :processing ? "Meeting capture uploaded for processing." : "Meeting capture stopped."

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
    refresh_session_note_after_speaker_update!
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
    MeetingSession.normalize_join_url(raw_url)
  end

  def attach_capture_files!(session)
    files = Array(meeting_session_params[:capture_files]).reject(&:blank?)
    return if files.empty?

    session.capture_files.attach(files)
  end

  def handle_session_dispatch!(session, force_online: false)
    if session.capture_mode == "online_bot"
      if !force_online && defer_online_dispatch?(session)
        schedule_online_session_jobs!(session)
        return :deferred
      end

      Meetings::BotDispatchService.new(session: session, actor: current_user).dispatch!
      schedule_online_session_jobs!(session)
      return :dispatched
    end

    return unless session.capture_files.attached?

    session.update!(status: "uploading", updated_by: current_user)
    Meetings::ProcessSessionJob.perform_later(session.id)
    :processing
  end

  def defer_online_dispatch?(session)
    event_start = session.kalendarium_event&.starts_at_utc
    return false if event_start.blank?

    event_start > Time.current
  end

  def schedule_online_session_jobs!(session)
    Meetings::OnlineSessionScheduleService.new(session: session).schedule!
  end

  def refresh_session_note_after_speaker_update!
    transcript = @meeting_session.transcript_text_from_utterances.to_s.strip
    return if transcript.blank?
    speaker_replacements = speaker_replacements_from_utterances(@meeting_session)
    updated_summary = replace_speaker_placeholders(@meeting_session.summary_markdown.to_s, speaker_replacements)
    updated_action_items = replace_speaker_names_in_actions(@meeting_session.action_items_json, speaker_replacements)

    @meeting_session.update!(
      transcript_text: transcript,
      summary_markdown: updated_summary,
      action_items_json: updated_action_items,
      updated_by: current_user
    )

    Meetings::NotaMaterializerService.new(session: @meeting_session, actor: current_user).upsert_session_output!(
      transcript_text: transcript,
      summary_markdown: updated_summary,
      action_items: updated_action_items
    )
  end

  def speaker_replacements_from_utterances(session)
    session.meeting_utterances.ordered.each_with_object({}) do |utterance, memo|
      number = utterance.speaker_key.to_s.delete_prefix("S").to_i
      next if number <= 0

      name = utterance.speaker_name.to_s.strip
      next if name.blank?

      memo["speaker #{number}"] = name
    end
  end

  def replace_speaker_placeholders(text, replacements)
    value = text.to_s
    return value if value.blank? || replacements.blank?

    replacements.each do |label, replacement|
      value = value.gsub(/\b#{Regexp.escape(label)}\b/i, replacement)
    end
    value
  end

  def replace_speaker_names_in_actions(action_items, replacements)
    normalized_replacements = replacements.transform_keys { |key| key.to_s.downcase }

    Array(action_items).map do |item|
      next item unless item.is_a?(Hash)

      updated = item.deep_dup
      owner = updated["owner"].to_s.strip
      if owner.present?
        mapped_owner = normalized_replacements[owner.downcase]
        updated["owner"] = mapped_owner if mapped_owner.present?
      end

      updated
    end
  end
end
