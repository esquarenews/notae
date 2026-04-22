require "rails_helper"

RSpec.describe "ops scripts" do
  it "keeps the backup and restore helpers shell-valid" do
    scripts = [
      Rails.root.join("script/ops/backup_notae_production.sh"),
      Rails.root.join("script/ops/restore_notae_production.sh"),
      Rails.root.join("script/ops/verify_notae_storage_recovery.sh"),
      Rails.root.join("script/ops/rehearse_storage_recovery_locally.sh")
    ]

    scripts.each do |script|
      expect(system("bash", "-n", script.to_s)).to be(true), "expected #{script} to pass bash -n"
    end
  end

  it "keeps the migration rollback readiness checker ruby-valid" do
    script = Rails.root.join("script/ops/check_migration_rollback_readiness.rb")

    expect(system("ruby", "-c", script.to_s)).to be(true), "expected #{script} to pass ruby -c"
  end
end
