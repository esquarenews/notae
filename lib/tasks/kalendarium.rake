namespace :kalendarium do
  desc "Queue Kalendarium sync jobs for enabled connections"
  task sync_due: :environment do
    KalendariumConnection.active.find_each do |connection|
      Kalendarium::SyncConnectionJob.perform_later(connection.id)
    rescue StandardError => error
      Rails.logger.warn("Failed to enqueue Kalendarium sync for #{connection.id}: #{error.class}: #{error.message}")
    end
  end

  desc "Dispatch due Kalendarium reminders"
  task dispatch_reminders: :environment do
    Kalendarium::ReminderDispatchJob.perform_later
  rescue StandardError => error
    Rails.logger.warn("Failed to enqueue Kalendarium reminders: #{error.class}: #{error.message}")
  end
end
