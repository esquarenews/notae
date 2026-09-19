require "digest"

module Analytics
  class ActivityRecorder
    class InvalidSample < StandardError; end

    MAX_SAMPLE_AGE = 2.minutes
    MAX_FUTURE_SKEW = 30.seconds
    SAMPLE_ID_PATTERN = /\A[a-zA-Z0-9_-]{8,80}\z/

    Result = Struct.new(:status, :bucket, :buckets, keyword_init: true)

    class << self
      def call(user:, workspace:, surface:, bucket_started_at:, duration_seconds:, sample_id: nil)
        new(
          user: user,
          workspace: workspace,
          surface: surface,
          bucket_started_at: bucket_started_at,
          duration_seconds: duration_seconds,
          sample_id: sample_id
        ).call
      end
    end

    def initialize(user:, workspace:, surface:, bucket_started_at:, duration_seconds:, sample_id:)
      @user = user
      @workspace = workspace
      @surface = surface.to_s
      @bucket_started_at = bucket_started_at
      @duration_seconds = duration_seconds
      @sample_id = sample_id
    end

    def call
      return Result.new(status: :disabled, buckets: []) unless tracking_enabled?
      raise InvalidSample, "Workspace is not available to this user." unless workspace_available?
      raise InvalidSample, "Unknown activity surface." unless AnalyticsActivityBucket::SURFACES.include?(surface)

      started_at = normalized_started_at
      seconds = normalized_duration
      identifier = normalized_sample_id(started_at:, seconds:)
      buckets = persist_segments(started_at:, seconds:, identifier:)

      Result.new(status: :recorded, bucket: buckets.first, buckets: buckets)
    end

    private

    attr_reader :user, :workspace, :surface, :bucket_started_at, :duration_seconds, :sample_id

    def tracking_enabled?
      return workspace.analytics_enabled? if workspace.present?

      Workspace.active
               .where(suspended_at: nil, analytics_enabled: true)
               .joins(:memberships)
               .where(memberships: { user_id: user.id })
               .exists?
    end

    def workspace_available?
      workspace.blank? || Membership.exists?(user_id: user.id, workspace_id: workspace.id)
    end

    def normalized_started_at
      parsed = Time.zone.parse(bucket_started_at.to_s)&.change(usec: 0)
      raise InvalidSample, "Activity timestamp is invalid." if parsed.blank?

      now = Time.current
      if parsed < now - MAX_SAMPLE_AGE || parsed > now + MAX_FUTURE_SKEW
        raise InvalidSample, "Activity timestamp is outside the accepted window."
      end

      parsed.utc
    rescue ArgumentError, TypeError
      raise InvalidSample, "Activity timestamp is invalid."
    end

    def normalized_duration
      seconds = Integer(duration_seconds, exception: false)
      raise InvalidSample, "Activity duration is invalid." if seconds.nil? || seconds <= 0

      seconds.clamp(1, AnalyticsActivityBucket::BUCKET_SECONDS)
    end

    def normalized_sample_id(started_at:, seconds:)
      candidate = sample_id.to_s.strip
      if candidate.blank?
        candidate = Digest::SHA256.hexdigest(
          [ user.id, workspace&.id, surface, started_at.iso8601, seconds ].join(":")
        )
      end
      raise InvalidSample, "Activity sample identifier is invalid." unless candidate.match?(SAMPLE_ID_PATTERN)

      candidate
    end

    def persist_segments(started_at:, seconds:, identifier:)
      interval_end = started_at + seconds.seconds
      cursor = started_at
      segments = []

      while cursor < interval_end
        bucket_start = Time.at(
          (cursor.to_i / AnalyticsActivityBucket::BUCKET_SECONDS) * AnalyticsActivityBucket::BUCKET_SECONDS
        ).utc
        segment_end = [ interval_end, bucket_start + AnalyticsActivityBucket::BUCKET_SECONDS.seconds ].min
        segments << [ bucket_start, (cursor - bucket_start).to_i, (segment_end - cursor).to_i ]
        cursor = segment_end
      end

      AnalyticsActivityBucket.transaction do
        segments.each_with_index.map do |(segment_started_at, segment_offset, segment_seconds), index|
          find_or_create_segment(
            identifier:,
            index:,
            started_at: segment_started_at,
            offset: segment_offset,
            seconds: segment_seconds
          )
        end
      end
    end

    def find_or_create_segment(identifier:, index:, started_at:, offset:, seconds:)
      AnalyticsActivityBucket.find_or_create_by!(user:, sample_id: identifier, segment_index: index) do |bucket|
        bucket.workspace = workspace
        bucket.surface = surface
        bucket.bucket_started_at = started_at
        bucket.segment_offset_seconds = offset
        bucket.duration_seconds = seconds
      end
    rescue ActiveRecord::RecordNotUnique
      retry
    end
  end
end
