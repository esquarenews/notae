namespace :epistularium do
  desc "Queue Epistularium sync jobs for enabled accounts"
  task sync_due: :environment do
    EpistulariumAccount.active.find_each do |account|
      next if account.last_synced_at.present? && account.last_synced_at > Epistularium::DueSyncScheduler::STALE_AFTER.ago

      Epistularium::SyncEnqueueService.new(
        account: account,
        mode: Epistularium::SyncEnqueueService.preferred_mode_for(account),
        throttle: 0
      ).call
    rescue StandardError => error
      Rails.logger.warn("Failed to enqueue Epistularium sync for #{account.id}: #{error.class}: #{error.message}")
    end
  end
end
