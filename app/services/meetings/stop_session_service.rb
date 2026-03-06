module Meetings
  class StopSessionService
    def initialize(session:, actor:, reason:, process_if_capture: true)
      @session = session
      @actor = actor
      @reason = reason
      @process_if_capture = process_if_capture
    end

    def call
      stop_active_bot_runs! if session.capture_mode == "online_bot"

      if process_if_capture && session.capture_files.attached?
        session.update!(
          status: "uploading",
          ended_at: Time.current,
          error_message: nil,
          updated_by: actor
        )
        Meetings::ProcessSessionJob.perform_later(session.id)
        :processing
      else
        session.update!(
          status: "cancelled",
          ended_at: Time.current,
          error_message: reason,
          updated_by: actor
        )
        :cancelled
      end
    end

    private

    attr_reader :session, :actor, :reason, :process_if_capture

    def stop_active_bot_runs!
      session.meeting_bot_runs.active.find_each do |run|
        run.update!(
          status: "failed",
          finished_at: Time.current,
          error_message: reason
        )
      end
    end
  end
end
