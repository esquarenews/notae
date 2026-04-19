namespace :epistularium do
  desc "Queue Epistularium sync jobs for enabled accounts"
  task sync_due: :environment do
    Notae::ScheduledTaskStore.track!("epistularium:sync_due") do
      Epistularium::DueSyncScheduler.new(accounts: EpistulariumAccount.active.to_a).call
    end
  end
end
