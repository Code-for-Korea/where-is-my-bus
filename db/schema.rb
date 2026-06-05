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

ActiveRecord::Schema[8.1].define(version: 2026_06_05_121757) do
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
    t.datetime "created_at", null: false
    t.string "license_plate", null: false
    t.string "pin", null: false
    t.datetime "updated_at", null: false
    t.index ["area_id", "license_plate"], name: "index_buses_on_area_id_and_license_plate", unique: true
    t.index ["area_id"], name: "index_buses_on_area_id"
  end

  create_table "regions", force: :cascade do |t|
    t.integer "areas_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_regions_on_name", unique: true
  end

  create_table "routes", force: :cascade do |t|
    t.integer "area_id", null: false
    t.datetime "created_at", null: false
    t.integer "headway_minutes"
    t.integer "likes_count", default: 0, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "stops_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["area_id", "name"], name: "index_routes_on_area_id_and_name", unique: true
    t.index ["area_id"], name: "index_routes_on_area_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "stops", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "route_id", null: false
    t.datetime "updated_at", null: false
    t.index ["route_id", "position"], name: "index_stops_on_route_id_and_position"
    t.index ["route_id"], name: "index_stops_on_route_id"
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
  add_foreign_key "routes", "areas"
  add_foreign_key "sessions", "users"
  add_foreign_key "stops", "routes"
end
