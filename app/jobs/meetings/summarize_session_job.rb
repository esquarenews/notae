module Meetings
  class SummarizeSessionJob < ApplicationJob
    queue_as :default

    def perform(meeting_session_id)
      session = MeetingSession.find_by(id: meeting_session_id)
      return if session.blank?

      summary = Meetings::SummaryAndActionsService.new(session: session).call
      session.update!(
        summary_markdown: summary[:summary_markdown],
        action_items_json: summary[:action_items],
        status: "proposing",
        error_message: nil
      )

      Meetings::NotaMaterializerService
        .new(session: session, actor: session.updated_by || session.created_by)
        .upsert_session_output!(
          transcript_text: session.transcript_text,
          summary_markdown: summary[:summary_markdown],
          action_items: summary[:action_items]
        )

      Meetings::GenerateActionProposalsJob.perform_later(session.id)
    rescue StandardError => error
      session&.update(status: "failed", error_message: error.message, processed_at: Time.current, ended_at: Time.current)
    end
  end
end
