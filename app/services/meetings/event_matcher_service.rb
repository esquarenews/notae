module Meetings
  class EventMatcherService
    MATCH_WINDOW = 18.hours

    def initialize(workspace:, join_url:, title: nil, reference_time: Time.current)
      @workspace = workspace
      @join_url = MeetingSession.normalize_join_url(join_url)
      @title = title.to_s.strip
      @reference_time = reference_time
    end

    def call
      return nil if join_url.blank?

      candidates = policy_scope
                   .where.not(status: "cancelled")
                   .where(starts_at_utc: (reference_time - MATCH_WINDOW)..(reference_time + MATCH_WINDOW))
                   .select { |event| MeetingSession.normalize_join_url(event.meeting_join_url) == join_url }
      return nil if candidates.empty?

      enabled_candidate = nearest(candidates.select(&:meeting_capture_enabled?))
      enabled_candidate || nearest(candidates)
    end

    private

    attr_reader :workspace, :join_url, :title, :reference_time

    def policy_scope
      KalendariumEvent.for_workspace(workspace)
    end

    def nearest(events)
      events.min_by do |event|
        [
          (event.starts_at_utc.to_i - reference_time.to_i).abs,
          title_distance(event),
          event.starts_at_utc.to_i
        ]
      end
    end

    def title_distance(event)
      return 1 if title.blank?

      event_title = event.title.to_s.strip.downcase
      return 0 if event_title == title.downcase
      return 0 if event_title.include?(title.downcase) || title.downcase.include?(event_title)

      1
    end
  end
end
