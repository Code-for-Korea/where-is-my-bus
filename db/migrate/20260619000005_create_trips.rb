class CreateTrips < ActiveRecord::Migration[8.1]
  def change
    create_table :trips do |t|
      t.integer  :bus_id, null: false
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end

    add_index :trips, :bus_id
    add_index :trips, [:bus_id, :ended_at]
    add_foreign_key :trips, :buses
  end
end
