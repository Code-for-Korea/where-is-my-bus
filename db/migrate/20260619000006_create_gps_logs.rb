class CreateGpsLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :gps_logs do |t|
      t.integer  :trip_id,     null: false
      t.decimal  :lat,         precision: 10, scale: 6, null: false
      t.decimal  :lng,         precision: 10, scale: 6, null: false
      t.datetime :recorded_at, null: false

      t.timestamps
    end

    add_index :gps_logs, :trip_id
    add_index :gps_logs, [:trip_id, :recorded_at]
    add_foreign_key :gps_logs, :trips
  end
end
