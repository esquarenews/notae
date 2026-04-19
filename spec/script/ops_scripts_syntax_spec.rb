require "rails_helper"

RSpec.describe "ops scripts" do
  it "keeps the backup and restore helpers shell-valid" do
    scripts = [
      Rails.root.join("script/ops/backup_notae_production.sh"),
      Rails.root.join("script/ops/restore_notae_production.sh"),
      Rails.root.join("script/ops/verify_notae_storage_recovery.sh")
    ]

    scripts.each do |script|
      expect(system("bash", "-n", script.to_s)).to be(true), "expected #{script} to pass bash -n"
    end
  end
end
