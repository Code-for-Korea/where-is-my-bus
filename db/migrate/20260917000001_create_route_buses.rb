class CreateRouteBuses < ActiveRecord::Migration[8.1]
  def change
    create_table :route_buses do |t|
      t.integer :route_id, null: false
      t.integer :bus_id, null: false

      t.timestamps
    end

    add_index :route_buses, [ :route_id, :bus_id ], unique: true
    add_index :route_buses, :bus_id
    add_foreign_key :route_buses, :routes
    add_foreign_key :route_buses, :buses
  end
end
