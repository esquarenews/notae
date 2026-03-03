class MeetingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    @upcoming_events = policy_scope(KalendariumEvent)
                         .for_workspace(@workspace)
                         .where("starts_at_utc >= ?", Time.current - 2.hours)
                         .where.not(status: "cancelled")
                         .where.not(metadata_json: {})
                         .order(:starts_at_utc)
                         .limit(30)
                         .to_a
                         .select { |event| event.meeting_join_url.present? }

    @meeting_sessions = policy_scope(MeetingSession)
                          .for_workspace(@workspace)
                          .includes(:kalendarium_event, :page, :meeting_utterances)
                          .recent_first
                          .limit(30)
                          .to_a

    @pending_action_proposals = policy_scope(KalendariumWriteProposal)
                                  .for_workspace(@workspace)
                                  .pending
                                  .where(user_id: current_user.id)
                                  .where("payload_json ->> 'meeting_session_id' IS NOT NULL")
                                  .recent_first
                                  .limit(20)
                                  .to_a

    @meeting_session = MeetingSession.new(
      workspace: @workspace,
      capture_mode: "upload",
      provider: "local",
      status: "scheduled"
    )
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end
end
