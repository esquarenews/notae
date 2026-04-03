class AddWorkspaceColorToWorkspaces < ActiveRecord::Migration[8.1]
  PALETTE = %w[
    #f43f5e
    #ec4899
    #d946ef
    #a855f7
    #8b5cf6
    #6366f1
    #3b82f6
    #0ea5e9
    #06b6d4
    #14b8a6
    #10b981
    #22c55e
    #84cc16
    #a3e635
    #eab308
    #f59e0b
    #f97316
    #ef4444
    #fb7185
    #f472b6
    #e879f9
    #9333ea
    #7c3aed
    #2563eb
    #0284c7
    #0891b2
    #0f766e
    #0d9488
    #16a34a
    #65a30d
    #ca8a04
    #c2410c
    #ea580c
    #be123c
    #475569
    #78716c
  ].freeze

  class MigrationWorkspace < ApplicationRecord
    self.table_name = "workspaces"
  end

  def up
    add_column :workspaces, :workspace_color, :string, null: false, default: PALETTE.first

    say_with_time "Assigning workspace colours" do
      MigrationWorkspace.reset_column_information

      MigrationWorkspace.find_each do |workspace|
        seed = workspace.slug.to_s.each_byte.sum
        workspace.update_columns(workspace_color: PALETTE[seed % PALETTE.length])
      end
    end
  end

  def down
    remove_column :workspaces, :workspace_color
  end
end
