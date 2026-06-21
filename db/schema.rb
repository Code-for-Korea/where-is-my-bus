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

ActiveRecord::Schema[8.1].define(version: 2026_06_21_035326) do
  create_table "areas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "region_id", null: false
    t.integer "routes_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["region_id", "name"], name: "index_areas_on_region_id_and_name", unique: true
    t.index ["region_id"], name: "index_areas_on_region_id"
  end

  create_table "buses", force: :cascade do |t|
    t.integer "area_id", null: false
    t.string "bus_number"
    t.datetime "created_at", null: false
    t.string "license_plate", null: false
    t.string "pin", null: false
    t.string "status", default: "active", null: false
    t.integer "traccar_device_id"
    t.string "traccar_unique_id"
    t.datetime "updated_at", null: false
    t.index ["area_id", "license_plate"], name: "index_buses_on_area_id_and_license_plate", unique: true
    t.index ["area_id"], name: "index_buses_on_area_id"
    t.index ["traccar_unique_id"], name: "index_buses_on_traccar_unique_id", unique: true
  end

  create_table "gps_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "lat", precision: 10, scale: 6, null: false
    t.decimal "lng", precision: 10, scale: 6, null: false
    t.datetime "recorded_at", null: false
    t.integer "trip_id", null: false
    t.datetime "updated_at", null: false
    t.index ["trip_id", "recorded_at"], name: "index_gps_logs_on_trip_id_and_recorded_at"
    t.index ["trip_id"], name: "index_gps_logs_on_trip_id"
  end

  create_table "pin_codes", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "bus_id", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bus_id"], name: "index_pin_codes_on_bus_id"
    t.index ["code"], name: "index_pin_codes_on_code", unique: true
  end

  create_table "regions", force: :cascade do |t|
    t.integer "areas_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "name_en"
    t.integer "position", default: 0, null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_regions_on_name", unique: true
    t.index ["slug"], name: "index_regions_on_slug", unique: true
  end

  create_table "routes", force: :cascade do |t|
    t.integer "area_id", null: false
    t.integer "bus_id"
    t.datetime "created_at", null: false
    t.integer "headway_minutes"
    t.integer "likes_count", default: 0, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "stops_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["area_id", "name"], name: "index_routes_on_area_id_and_name", unique: true
    t.index ["area_id"], name: "index_routes_on_area_id"
    t.index ["bus_id"], name: "index_routes_on_bus_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "stop_likes", force: :cascade do |t|
    t.integer "bus_id", null: false
    t.datetime "created_at", null: false
    t.string "session_token", null: false
    t.integer "stop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["session_token", "stop_id"], name: "index_stop_likes_on_session_token_and_stop_id"
    t.index ["stop_id", "bus_id", "session_token"], name: "index_stop_likes_on_stop_id_and_bus_id_and_session_token"
    t.index ["stop_id", "session_token", "created_at"], name: "index_stop_likes_on_stop_session_created"
  end

  create_table "stops", force: :cascade do |t|
    t.integer "avg_travel_seconds"
    t.datetime "created_at", null: false
    t.decimal "lat", precision: 10, scale: 6
    t.decimal "lng", precision: 10, scale: 6
    t.string "name", null: false
    t.string "name_en"
    t.integer "route_id", null: false
    t.integer "sequence", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["route_id", "sequence"], name: "index_stops_on_route_id_and_sequence"
    t.index ["route_id"], name: "index_stops_on_route_id"
  end

  create_table "trips", force: :cascade do |t|
    t.integer "bus_id", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.index ["bus_id", "ended_at"], name: "index_trips_on_bus_id_and_ended_at"
    t.index ["bus_id"], name: "index_trips_on_bus_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "areas", "regions"
  add_foreign_key "buses", "areas"
  add_foreign_key "gps_logs", "trips"
  add_foreign_key "pin_codes", "buses"
  add_foreign_key "routes", "areas"
  add_foreign_key "routes", "buses"
  add_foreign_key "sessions", "users"
  add_foreign_key "stop_likes", "buses"
  add_foreign_key "stop_likes", "stops"
  add_foreign_key "stops", "routes"
  add_foreign_key "trips", "buses"
end
