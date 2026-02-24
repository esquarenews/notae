class AddPositionToDbRows < ActiveRecord::Migration[8.1]
  def change
    add_column :db_rows, :position, :integer, null: false, default: 1024
    add_index :db_rows, %i[database_id position]
    add_check_constraint :db_rows, "position > 0", name: "check_db_rows_position_positive"

    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE db_rows
          SET position = ranked.pos
          FROM (
            SELECT id,
                   (ROW_NUMBER() OVER (PARTITION BY database_id ORDER BY created_at, id) * 1024) AS pos
            FROM db_rows
          ) ranked
          WHERE db_rows.id = ranked.id
        SQL
      end
    end
  end
end
