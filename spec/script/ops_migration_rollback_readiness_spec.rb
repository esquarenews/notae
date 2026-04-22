require "rails_helper"
require "fileutils"
require "open3"
require "tmpdir"

RSpec.describe "migration rollback readiness checker" do
  let(:script_path) { Rails.root.join("script/ops/check_migration_rollback_readiness.rb") }

  it "passes strict mode for reversible risky migrations" do
    Dir.mktmpdir("notae-migration-readiness") do |tmpdir|
      migration = File.join(tmpdir, "20260422000000_remove_legacy_column.rb")
      File.write(migration, <<~RUBY)
        class RemoveLegacyColumn < ActiveRecord::Migration[8.0]
          def up
            remove_column :pages, :legacy_title
          end

          def down
            add_column :pages, :legacy_title, :string
          end
        end
      RUBY

      stdout, status = Open3.capture2e("ruby", script_path.to_s, "--strict", migration)

      expect(status.success?).to be(true), stdout
      expect(stdout).to include("REVIEW")
      expect(stdout).to include("rollback path: code-supported: explicit down")
    end
  end

  it "fails strict mode for risky migrations without a rollback path" do
    Dir.mktmpdir("notae-migration-readiness-risky") do |tmpdir|
      migration = File.join(tmpdir, "20260422000001_drop_legacy_table.rb")
      File.write(migration, <<~RUBY)
        class DropLegacyTable < ActiveRecord::Migration[8.0]
          def change
            drop_table :legacy_events
          end
        end
      RUBY

      stdout, status = Open3.capture2e("ruby", script_path.to_s, "--strict", migration)

      expect(status.success?).to be(false), stdout
      expect(stdout).to include("BACKUP_REQUIRED")
      expect(stdout).to include("rollback path: restore-only: needs backup rehearsal")
    end
  end
end
