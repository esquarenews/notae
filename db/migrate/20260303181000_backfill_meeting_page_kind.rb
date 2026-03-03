class BackfillMeetingPageKind < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    execute <<~SQL.squish
      UPDATE pages
      SET page_kind = 'meeting_note'
      WHERE page_kind = 'nota'
        AND LOWER(title) LIKE '%meeting%'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE pages
      SET page_kind = 'nota'
      WHERE page_kind = 'meeting_note'
    SQL
  end
end
