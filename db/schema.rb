# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_23_151932) do
  create_table "buses", force: :cascade do |t|
    t.string "bus_number"
    t.datetime "created_at", null: false
    t.string "license_plate", null: false
    t.string "pin", null: false
    t.datetime "pin_registered_at"
    t.integer "route_id"
    t.integer "traccar_device_id"
    t.string "traccar_unique_id", null: false
    t.datetime "updated_at", null: false
    t.index ["license_plate"], name: "index_buses_on_license_plate", unique: true
    t.index ["pin"], name: "index_buses_on_pin", unique: true
    t.index ["route_id"], name: "index_buses_on_route_id"
    t.index ["traccar_device_id"], name: "index_buses_on_traccar_device_id", unique: true
    t.index ["traccar_unique_id"], name: "index_buses_on_traccar_unique_id", unique: true
  end

  create_table "route_stops", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "route_id", null: false
    t.integer "sequence", null: false
    t.integer "stop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["route_id", "sequence"], name: "index_route_stops_on_route_id_and_sequence", unique: true
    t.index ["route_id", "stop_id"], name: "index_route_stops_on_route_id_and_stop_id", unique: true
    t.index ["route_id"], name: "index_route_stops_on_route_id"
    t.index ["stop_id"], name: "index_route_stops_on_stop_id"
  end

  create_table "routes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "traccar_group_id"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_routes_on_name", unique: true
    t.index ["traccar_group_id"], name: "index_routes_on_traccar_group_id", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "stop_visits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "entered_at", null: false
    t.string "entered_event_id"
    t.datetime "exited_at"
    t.string "exited_event_id"
    t.integer "stop_id", null: false
    t.integer "trip_id", null: false
    t.datetime "updated_at", null: false
    t.index ["entered_event_id"], name: "index_stop_visits_on_entered_event_id", unique: true
    t.index ["exited_event_id"], name: "index_stop_visits_on_exited_event_id", unique: true
    t.index ["stop_id"], name: "index_stop_visits_on_stop_id"
    t.index ["trip_id", "entered_at"], name: "index_stop_visits_on_trip_id_and_entered_at"
    t.index ["trip_id"], name: "index_stop_visits_on_trip_id"
  end

  create_table "stops", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "lat", precision: 10, scale: 6, null: false
    t.decimal "lng", precision: 10, scale: 6, null: false
    t.string "name", null: false
    t.integer "traccar_geofence_id"
    t.datetime "updated_at", null: false
    t.index ["traccar_geofence_id"], name: "index_stops_on_traccar_geofence_id", unique: true
  end

  create_table "trips", force: :cascade do |t|
    t.integer "bus_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.integer "route_id", null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bus_id"], name: "index_trips_on_bus_id"
    t.index ["bus_id"], name: "index_trips_on_bus_id_active", unique: true, where: "ended_at IS NULL"
    t.index ["route_id", "ended_at"], name: "index_trips_on_route_id_and_ended_at"
    t.index ["route_id"], name: "index_trips_on_route_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "buses", "routes"
  add_foreign_key "route_stops", "routes"
  add_foreign_key "route_stops", "stops"
  add_foreign_key "sessions", "users"
  add_foreign_key "stop_visits", "stops"
  add_foreign_key "stop_visits", "trips"
  add_foreign_key "trips", "buses"
  add_foreign_key "trips", "routes"
end
