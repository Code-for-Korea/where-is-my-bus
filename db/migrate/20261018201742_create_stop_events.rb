class CreateStopEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :stop_events do |t|
      t.references :bus, null: false, foreign_key: true
      t.references :stop, null: false, foreign_key: true
      t.string :event_type, null: false
      t.datetime :occurred_at, null: false
      t.string :dedup_key, null: false

      t.timestamps
    end

    add_index :stop_events, :dedup_key, unique: true
    add_index :stop_events, [ :bus_id, :occurred_at ]
    add_index :stop_events, [ :stop_id, :occurred_at ]
  end
end
