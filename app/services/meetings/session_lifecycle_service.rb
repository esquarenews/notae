module Meetings
  class SessionLifecycleService
    def initialize(workspace:, actor:)
      @workspace = workspace
      @actor = actor
    end

    def create_session!(title:, capture_mode:, provider:, kalendarium_event: nil, join_url: nil, consent_warning_acknowledged: false, force_new: false)
      existing = existing_active_session_for(kalendarium_event)
      return existing if existing.present? && !force_new

      resolved_join_url = MeetingSession.normalize_join_url(join_url.presence || kalendarium_event&.meeting_join_url)
      if capture_mode.to_s == "online_bot" && resolved_join_url.blank?
        raise ArgumentError, "Meeting URL is required unless the selected event has a join link."
      end

      session = MeetingSession.new(
        workspace: workspace,
        title: title.to_s.strip.presence || default_title_for(kalendarium_event),
        capture_mode: capture_mode,
        provider: provider,
        kalendarium_event: kalendarium_event,
        join_url: resolved_join_url,
        created_by: actor,
        updated_by: actor,
        status: "scheduled",
        consent_warning_seen_at: consent_warning_acknowledged ? Time.current : nil
      )

      ActiveRecord::Base.transaction do
        session.save!
        page = Meetings::NotaMaterializerService.new(session: session, actor: actor).ensure_linked_nota!
        session.update!(page: page) if session.page_id != page.id
        if kalendarium_event.present? && kalendarium_event.linked_page_id != page.id
          kalendarium_event.update!(linked_page: page, updated_by: actor)
        end
      end
      session
    end

    def transition!(session:, to_status:)
      return session if session.status == to_status

      raise ArgumentError, "Invalid meeting session status: #{to_status}" unless MeetingSession::STATUSES.include?(to_status)
      session.update!(
        status: to_status,
        updated_by: actor,
        started_at: session.started_at.presence || (to_status == "recording" ? Time.current : nil),
        ended_at: ((to_status == "cancelled" || to_status == "failed" || to_status == "completed") ? Time.current : session.ended_at),
        processed_at: to_status == "completed" ? Time.current : session.processed_at
      )
      session
    end

    private

    attr_reader :workspace, :actor

    def default_title_for(kalendarium_event)
      return "#{kalendarium_event.title} meeting" if kalendarium_event&.title.present?

      "Meeting notes"
    end
    def existing_active_session_for(kalendarium_event)
      return nil if kalendarium_event.blank?

      MeetingSession.for_workspace(workspace)
                    .where(kalendarium_event_id: kalendarium_event.id)
                    .active
                    .order(created_at: :desc)
                    .first
    end
  end
end
