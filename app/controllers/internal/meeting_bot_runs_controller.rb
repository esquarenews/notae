module Internal
  class MeetingBotRunsController < ActionController::API
    before_action :authenticate_internal_worker!
    before_action :set_run, only: %i[heartbeat upload_complete failed]

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
          failed_path: failed_internal_meeting_bot_run_path(run)
        }
      }, status: :ok
    end

    def heartbeat
      metadata = @run.metadata_json.to_h
      metadata["heartbeat_payload"] = heartbeat_params.to_h if heartbeat_params.present?
      @run.update!(
        status: normalized_status(@run.status),
        last_heartbeat_at: Time.current,
        metadata_json: metadata
      )

      render json: { ok: true }, status: :ok
    end

    def upload_complete
      upload_file = params[:file]
      if upload_file.blank?
        render json: { error: { code: "missing_file", message: "file is required" } }, status: :unprocessable_entity
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

    def failed
      @run.update!(
        status: "failed",
        error_message: params[:error_message].to_s.truncate(500),
        finished_at: Time.current,
        last_heartbeat_at: Time.current
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

    def normalized_status(default_status)
      requested = heartbeat_params[:status].to_s
      return default_status if requested.blank?
      return requested if MeetingBotRun::STATUSES.include?(requested)

      default_status
    end
  end
end
