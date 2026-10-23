class CreateDomainTables < ActiveRecord::Migration[8.1]
  def change
    create_table :routes do |t|
      t.string :name, null: false
      t.integer :traccar_group_id

      t.timestamps
    end
    add_index :routes, :name, unique: true
    add_index :routes, :traccar_group_id, unique: true

    create_table :stops do |t|
      t.string :name, null: false
      t.decimal :lat, precision: 10, scale: 6, null: false
      t.decimal :lng, precision: 10, scale: 6, null: false
      t.integer :traccar_geofence_id

      t.timestamps
    end
    add_index :stops, :traccar_geofence_id, unique: true

    create_table :route_stops do |t|
      t.references :route, null: false, foreign_key: true
      t.references :stop, null: false, foreign_key: true
      t.integer :sequence, null: false

      t.timestamps
    end
    add_index :route_stops, %i[route_id stop_id], unique: true
    add_index :route_stops, %i[route_id sequence], unique: true

    create_table :buses do |t|
      t.string :license_plate, null: false
      t.string :bus_number
      t.string :pin, null: false
      t.datetime :pin_registered_at
      t.string :traccar_unique_id, null: false
      t.integer :traccar_device_id

      t.timestamps
    end
    add_index :buses, :license_plate, unique: true
    add_index :buses, :pin, unique: true
    add_index :buses, :traccar_unique_id, unique: true
    add_index :buses, :traccar_device_id, unique: true

    create_table :trips do |t|
      t.references :bus, null: false, foreign_key: true
      t.references :route, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :ended_at

      t.timestamps
    end
    # 버스당 진행 중인 운행(ended_at IS NULL)은 하나만 허용한다.
    add_index :trips, :bus_id, unique: true, where: "ended_at IS NULL", name: "index_trips_on_bus_id_active"
    add_index :trips, %i[route_id ended_at]

    create_table :stop_visits do |t|
      t.references :trip, null: false, foreign_key: true
      t.references :stop, null: false, foreign_key: true
      t.datetime :entered_at, null: false
      t.datetime :exited_at
      t.string :entered_event_id
      t.string :exited_event_id

      t.timestamps
    end
    add_index :stop_visits, %i[trip_id entered_at]
    add_index :stop_visits, :entered_event_id, unique: true
    add_index :stop_visits, :exited_event_id, unique: true
  end
end
