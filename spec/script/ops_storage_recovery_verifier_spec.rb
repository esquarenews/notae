require "rails_helper"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe "storage recovery verifier script" do
  let(:script_path) { Rails.root.join("script/ops/verify_notae_storage_recovery.sh") }

  it "passes when restored storage contains every archived file" do
    Dir.mktmpdir("notae-storage-recovery") do |tmpdir|
      backup_dir = File.join(tmpdir, "backup")
      source_storage = File.join(tmpdir, "source_storage")
      restored_storage = File.join(tmpdir, "restored_storage")

      FileUtils.mkdir_p(File.join(source_storage, "uploads/2026/04"))
      File.write(File.join(source_storage, "uploads/2026/04/sample.txt"), "sample")
      FileUtils.mkdir_p(File.join(source_storage, "covers"))
      File.write(File.join(source_storage, "covers/cover.jpg"), "cover")

      FileUtils.mkdir_p(backup_dir)
      system("tar", "-C", tmpdir, "-czf", File.join(backup_dir, "storage.tar.gz"), File.basename(source_storage))
      FileUtils.cp_r(source_storage, restored_storage)

      stdout, status = Open3.capture2e(
        "bash",
        script_path.to_s,
        backup_dir,
        restored_storage,
        "uploads/2026/04/sample.txt"
      )

      expect(status.success?).to be(true), stdout
      expect(stdout).to include("Storage recovery verification passed.")
      expect(stdout).to include("Verified expected file: uploads/2026/04/sample.txt")
    end
  end

  it "fails when a file from the archive is missing in restored storage" do
    Dir.mktmpdir("notae-storage-recovery-missing") do |tmpdir|
      backup_dir = File.join(tmpdir, "backup")
      source_storage = File.join(tmpdir, "source_storage")
      restored_storage = File.join(tmpdir, "restored_storage")

      FileUtils.mkdir_p(File.join(source_storage, "uploads"))
      File.write(File.join(source_storage, "uploads/sample.txt"), "sample")
      File.write(File.join(source_storage, "uploads/other.txt"), "other")

      FileUtils.mkdir_p(backup_dir)
      system("tar", "-C", tmpdir, "-czf", File.join(backup_dir, "storage.tar.gz"), File.basename(source_storage))
      FileUtils.cp_r(source_storage, restored_storage)
      FileUtils.rm_f(File.join(restored_storage, "uploads/other.txt"))

      stdout, status = Open3.capture2e(
        "bash",
        script_path.to_s,
        backup_dir,
        restored_storage
      )

      expect(status.success?).to be(false), stdout
      expect(stdout).to include("Missing files from restored storage:")
      expect(stdout).to include("uploads/other.txt")
    end
  end
end
