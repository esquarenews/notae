module Meetings
  class BotDispatchService
    def initialize(session:, actor:)
      @session = session
      @actor = actor
    end

    def dispatch!
      return session unless session.capture_mode == "online_bot"

      run = session.meeting_bot_runs.active.order(created_at: :desc).first
      if run.blank?
        run = session.meeting_bot_runs.create!(
          provider: session.provider,
          status: "queued",
          metadata_json: {
            "join_url" => session.join_url.to_s,
            "workspace_id" => session.workspace_id,
            "created_by_id" => actor.id
          }
        )
      end

      session.update!(status: "joining", updated_by: actor)
      Meetings::StartBotRunJob.perform_later(run.id)
      session
    end

    private

    attr_reader :session, :actor
  end
end
