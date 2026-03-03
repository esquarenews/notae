namespace :meetings do
  desc "Queue due meeting captures for events with capture enabled"
  task schedule_due: :environment do
    Meetings::ScheduleDueCapturesJob.perform_later
  rescue StandardError => error
    Rails.logger.warn("Failed to enqueue due meeting captures: #{error.class}: #{error.message}")
  end

  desc "Reconcile stale bot runs and mark sessions failed when heartbeat is stale"
  task reconcile_runs: :environment do
    stale_cutoff = 10.minutes.ago
    MeetingBotRun.where(status: %w[claimed joining recording uploading])
                 .where("last_heartbeat_at IS NOT NULL AND last_heartbeat_at < ?", stale_cutoff)
                 .find_each do |run|
      run.update!(
        status: "failed",
        finished_at: Time.current,
        error_message: "Worker heartbeat timed out."
      )
      run.meeting_session.update!(
        status: "failed",
        error_message: "Meeting bot worker timed out.",
        ended_at: Time.current
      )
    end
  end

  desc "Retry failed processing for sessions that still have capture files"
  task retry_failed_processing: :environment do
    MeetingSession.where(status: "failed").includes(:capture_files_attachments).find_each do |session|
      next unless session.capture_files.attached?

      session.update!(status: "processing", error_message: nil)
      Meetings::ProcessSessionJob.perform_later(session.id)
    end
  end
end
