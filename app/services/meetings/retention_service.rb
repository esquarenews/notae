module Meetings
  class RetentionService
    def initialize(session:)
      @session = session
    end

    def purge_raw_captures!
      return if session.capture_files.blank?

      session.capture_files.each(&:purge)
      metadata = session.metadata_json.to_h
      metadata["raw_capture_purged_at"] = Time.current.utc.iso8601
      session.update_columns(metadata_json: metadata, updated_at: Time.current)
    end

    private

    attr_reader :session
  end
end
