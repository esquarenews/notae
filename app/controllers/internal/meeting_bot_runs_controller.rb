module Internal
  class MeetingBotRunsController < ActionController::API
    MAX_UPLOAD_BYTES = 250.megabytes

    before_action :authenticate_internal_worker!
    before_action :set_run, only: %i[heartbeat upload_complete transcript_complete failed]

    def claim
      run = claim_next_run
      head :no_content and return if run.blank?

      render json: {
        data: {
          id: run.id,
          meeting_session_id: run.meeting_session_id,
          provider: run.provider,
          join_url: run.meeting_session.join_url,
          workspace_id: run.meeting_session.workspace_id,
          heartbeat_path: heartbeat_internal_meeting_bot_run_path(run),
          upload_complete_path: upload_complete_internal_meeting_bot_run_path(run),
          transcript_complete_path: transcript_complete_internal_meeting_bot_run_path(run),
          failed_path: failed_internal_meeting_bot_run_path(run)
        }
      }, status: :ok
    end

    def heartbeat
      if worker_should_stop?
        render json: { ok: false, continue: false, run_status: @run.status, session_status: @run.meeting_session.status }, status: :conflict
        return
      end

      metadata = @run.metadata_json.to_h
      metadata["heartbeat_payload"] = heartbeat_params.to_h if heartbeat_params.present?
      requested_status = normalized_status(@run.status)
      @run.update!(
        status: requested_status,
        last_heartbeat_at: Time.current,
        metadata_json: metadata
      )
      synchronize_session_status_from_run!(requested_status)

      render json: { ok: true, continue: true }, status: :ok
    end

    def upload_complete
      upload_file = params[:file]
      if upload_file.blank?
        render json: { error: { code: "missing_file", message: "file is required" } }, status: :unprocessable_entity
        return
      end

      if @run.status.in?(%w[finished failed])
        render json: { error: { code: "invalid_state", message: "Run is no longer accepting uploads." } }, status: :conflict
        return
      end

      validation_error = validate_upload_file(upload_file)
      if validation_error.present?
        render json: { error: { code: "invalid_file", message: validation_error } }, status: :unprocessable_entity
        return
      end

      @run.meeting_session.capture_files.attach(upload_file)
      @run.update!(
        status: "finished",
        finished_at: Time.current,
        last_heartbeat_at: Time.current
      )
      @run.meeting_session.update!(status: "processing", error_message: nil)
      Meetings::ProcessSessionJob.perform_later(@run.meeting_session.id)

      render json: { ok: true }, status: :ok
    end

    def transcript_complete
      utterances = transcript_complete_params[:utterances]
      transcript_text = transcript_complete_params[:transcript_text]
      if Array(utterances).empty? && transcript_text.to_s.strip.blank?
        render json: { error: { code: "missing_transcript", message: "utterances or transcript_text is required" } }, status: :unprocessable_entity
        return
      end

      Meetings::TranscriptIngestService.new(
        session: @run.meeting_session,
        actor: @run.meeting_session.updated_by || @run.meeting_session.created_by
      ).ingest!(
        utterances: Array(utterances),
        transcript_text: transcript_text,
        metadata: transcript_complete_params[:metadata].to_h.merge(
          "worker_id" => @run.worker_id.to_s.presence,
          "bot_provider" => @run.provider,
          "transcript_source" => "meeting_bot_captions"
        ).compact
      )

      @run.update!(
        status: "finished",
        finished_at: Time.current,
        last_heartbeat_at: Time.current,
        error_message: nil
      )

      render json: { ok: true }, status: :ok
    rescue Meetings::TranscriptIngestService::Error => error
      render json: { error: { code: "invalid_transcript", message: error.message } }, status: :unprocessable_entity
    end

    def failed
      metadata = @run.metadata_json.to_h
      metadata.merge!(sanitized_failure_metadata) if failed_params[:metadata].present?
      @run.update!(
        status: "failed",
        error_message: failed_params[:error_message].to_s.truncate(500),
        finished_at: Time.current,
        last_heartbeat_at: Time.current,
        metadata_json: metadata
      )
      @run.meeting_session.update!(
        status: "failed",
        error_message: @run.error_message,
        ended_at: Time.current
      )

      render json: { ok: true }, status: :ok
    end

    private

    def set_run
      @run = MeetingBotRun.find(params[:id])
    end

    def authenticate_internal_worker!
      configured_token = ENV["MEETING_BOT_INTERNAL_TOKEN"].to_s
      provided_token = extracted_token
      if configured_token.blank? || provided_token.blank? || !ActiveSupport::SecurityUtils.secure_compare(provided_token, configured_token)
        render json: { error: { code: "unauthorized", message: "Valid internal worker token required" } }, status: :unauthorized
      end
    end

    def extracted_token
      bearer = request.authorization.to_s
      return bearer.delete_prefix("Bearer ").strip if bearer.start_with?("Bearer ")

      request.headers["X-Internal-Token"].to_s.strip
    end

    def claim_next_run
      worker_id = params[:worker_id].to_s.strip.presence
      now = Time.current

      MeetingBotRun.transaction do
        candidate = MeetingBotRun.where(status: "queued").order(:created_at).lock("FOR UPDATE SKIP LOCKED").first
        if candidate.present?
          candidate.update!(
            status: "claimed",
            worker_id: worker_id,
            claimed_at: now,
            last_heartbeat_at: now
          )
          candidate.meeting_session.update!(status: "joining", error_message: nil)
        end
        candidate
      end
    end

    def heartbeat_params
      params.permit(:status, :worker_id, :error_message, metadata: {})
    end

    def transcript_complete_params
      params.permit(:transcript_text, metadata: {}, utterances: [ :speaker_key, :speaker_name, :text, :started_ms, :ended_ms, :confidence ])
    end

    def failed_params
      params.permit(:error_message, metadata: {})
    end

    def sanitized_failure_metadata
      failed_params[:metadata].to_h.except("page_body_excerpt")
    end

    def validate_upload_file(upload_file)
      content_type = upload_file.content_type.to_s.strip
      upload_size = upload_size_for(upload_file)

      return "file is empty" if upload_size <= 0
      return "file exceeds 250 MB" if upload_size > MAX_UPLOAD_BYTES
      return nil if media_content_type?(content_type)

      "Only audio or video uploads are supported."
    end

    def upload_size_for(upload_file)
      if upload_file.respond_to?(:size)
        upload_file.size.to_i
      elsif upload_file.respond_to?(:tempfile) && upload_file.tempfile.present?
        upload_file.tempfile.size.to_i
      else
        0
      end
    end

    def media_content_type?(content_type)
      return true if content_type.start_with?("audio/", "video/")

      content_type == "application/octet-stream"
    end

    def normalized_status(default_status)
      requested = heartbeat_params[:status].to_s
      return default_status if requested.blank?
      return requested if MeetingBotRun::STATUSES.include?(requested)

      default_status
    end

    def worker_should_stop?
      return true if @run.status == "finished"

      @run.meeting_session.status.in?(%w[cancelled completed failed])
    end

    def synchronize_session_status_from_run!(run_status)
      mapped_status = case run_status
      when "claimed", "joining", "queued"
        "joining"
      when "recording"
        "recording"
      when "uploading"
        "uploading"
      when "failed"
        "failed"
      else
        nil
      end
      return if mapped_status.blank?

      updates = { status: mapped_status }
      updates[:started_at] = Time.current if mapped_status == "recording" && @run.meeting_session.started_at.blank?
      if mapped_status == "failed"
        updates[:ended_at] = Time.current
        updates[:error_message] = heartbeat_params[:error_message].to_s.truncate(500).presence || @run.error_message
      else
        updates[:error_message] = nil if @run.meeting_session.error_message.present?
      end

      @run.meeting_session.update!(updates)
    end
  end
end
