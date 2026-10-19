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

ActiveRecord::Schema[8.1].define(version: 2026_10_19_132304) do
  create_table "areas", force: :cascade do |t|
    t.integer "region_id", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "routes_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["region_id", "name"], name: "index_areas_on_region_id_and_name", unique: true
    t.index ["region_id"], name: "index_areas_on_region_id"
  end

  create_table "buses", force: :cascade do |t|
    t.integer "area_id", null: false
    t.string "license_plate", null: false
    t.string "pin", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "bus_number"
    t.string "status", default: "active", null: false
    t.integer "traccar_device_id"
    t.string "traccar_unique_id"
    t.datetime "pin_registered_at"
    t.index ["area_id", "license_plate"], name: "index_buses_on_area_id_and_license_plate", unique: true
    t.index ["area_id"], name: "index_buses_on_area_id"
    t.index ["pin"], name: "index_buses_on_pin", unique: true
    t.index ["traccar_unique_id"], name: "index_buses_on_traccar_unique_id", unique: true
  end

  create_table "current_positions", force: :cascade do |t|
    t.integer "bus_id", null: false
    t.decimal "lat", precision: 10, scale: 6, null: false
    t.decimal "lng", precision: 10, scale: 6, null: false
    t.float "speed"
    t.float "bearing"
    t.float "accuracy"
    t.integer "battery"
    t.datetime "recorded_at", null: false
    t.datetime "received_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bus_id"], name: "index_current_positions_on_bus_id", unique: true
  end

  create_table "devices", force: :cascade do |t|
    t.integer "bus_id", null: false
    t.string "unique_id", null: false
    t.string "credential_digest"
    t.datetime "last_seen_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bus_id"], name: "index_devices_on_bus_id", unique: true
    t.index ["unique_id"], name: "index_devices_on_unique_id", unique: true
  end

  create_table "gps_logs", force: :cascade do |t|
    t.integer "trip_id", null: false
    t.decimal "lat", precision: 10, scale: 6, null: false
    t.decimal "lng", precision: 10, scale: 6, null: false
    t.datetime "recorded_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["trip_id", "recorded_at"], name: "index_gps_logs_on_trip_id_and_recorded_at"
    t.index ["trip_id"], name: "index_gps_logs_on_trip_id"
  end

  create_table "pin_codes", force: :cascade do |t|
    t.integer "bus_id", null: false
    t.string "code", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bus_id"], name: "index_pin_codes_on_bus_id"
    t.index ["code"], name: "index_pin_codes_on_code", unique: true
  end

  create_table "position_histories", force: :cascade do |t|
    t.integer "bus_id", null: false
    t.decimal "lat", precision: 10, scale: 6, null: false
    t.decimal "lng", precision: 10, scale: 6, null: false
    t.float "speed"
    t.float "bearing"
    t.float "accuracy"
    t.integer "battery"
    t.datetime "recorded_at", null: false
    t.datetime "received_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bus_id", "recorded_at"], name: "index_position_histories_on_bus_id_and_recorded_at"
    t.index ["bus_id"], name: "index_position_histories_on_bus_id"
  end

  create_table "regions", force: :cascade do |t|
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "areas_count", default: 0, null: false
    t.string "slug"
    t.string "name_en"
    t.index ["name"], name: "index_regions_on_name", unique: true
    t.index ["slug"], name: "index_regions_on_slug", unique: true
  end

  create_table "route_buses", force: :cascade do |t|
    t.integer "route_id", null: false
    t.integer "bus_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bus_id"], name: "index_route_buses_on_bus_id"
    t.index ["route_id", "bus_id"], name: "index_route_buses_on_route_id_and_bus_id", unique: true
  end

  create_table "route_segment_stats", force: :cascade do |t|
    t.integer "route_id", null: false
    t.integer "from_stop_id", null: false
    t.integer "to_stop_id", null: false
    t.integer "hour_of_day", null: false
    t.date "date", null: false
    t.float "avg_seconds", null: false
    t.integer "samples_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["from_stop_id"], name: "index_route_segment_stats_on_from_stop_id"
    t.index ["route_id", "from_stop_id", "to_stop_id", "hour_of_day", "date"], name: "index_route_segment_stats_on_segment_and_hour_and_date", unique: true
    t.index ["route_id"], name: "index_route_segment_stats_on_route_id"
    t.index ["to_stop_id"], name: "index_route_segment_stats_on_to_stop_id"
  end

  create_table "routes", force: :cascade do |t|
    t.integer "area_id", null: false
    t.string "name", null: false
    t.integer "headway_minutes"
    t.integer "likes_count", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.integer "stops_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "traccar_group_id"
    t.index ["area_id", "name"], name: "index_routes_on_area_id_and_name", unique: true
    t.index ["area_id"], name: "index_routes_on_area_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.string "key", null: false
    t.string "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "stop_events", force: :cascade do |t|
    t.integer "bus_id", null: false
    t.integer "stop_id", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.string "dedup_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bus_id", "occurred_at"], name: "index_stop_events_on_bus_id_and_occurred_at"
    t.index ["bus_id"], name: "index_stop_events_on_bus_id"
    t.index ["dedup_key"], name: "index_stop_events_on_dedup_key", unique: true
    t.index ["stop_id", "occurred_at"], name: "index_stop_events_on_stop_id_and_occurred_at"
    t.index ["stop_id"], name: "index_stop_events_on_stop_id"
  end

  create_table "stop_likes", force: :cascade do |t|
    t.integer "stop_id", null: false
    t.integer "bus_id", null: false
    t.string "session_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["session_token", "stop_id"], name: "index_stop_likes_on_session_token_and_stop_id"
    t.index ["stop_id", "bus_id", "session_token"], name: "index_stop_likes_on_stop_id_and_bus_id_and_session_token"
    t.index ["stop_id", "session_token", "created_at"], name: "index_stop_likes_on_stop_session_created"
  end

  create_table "stops", force: :cascade do |t|
    t.integer "route_id", null: false
    t.string "name", null: false
    t.integer "sequence", default: 0, null: false
    t.decimal "lat", precision: 10, scale: 6
    t.decimal "lng", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "avg_travel_seconds"
    t.string "name_en"
    t.integer "traccar_geofence_id"
    t.index ["route_id", "sequence"], name: "index_stops_on_route_id_and_sequence"
    t.index ["route_id"], name: "index_stops_on_route_id"
  end

  create_table "trips", force: :cascade do |t|
    t.integer "bus_id", null: false
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["bus_id", "ended_at"], name: "index_trips_on_bus_id_and_ended_at"
    t.index ["bus_id"], name: "index_trips_on_bus_id"
    t.index ["bus_id"], name: "index_trips_on_bus_id_when_active", unique: true, where: "ended_at IS NULL"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "areas", "regions"
  add_foreign_key "buses", "areas"
  add_foreign_key "current_positions", "buses"
  add_foreign_key "devices", "buses"
  add_foreign_key "gps_logs", "trips"
  add_foreign_key "pin_codes", "buses"
  add_foreign_key "position_histories", "buses"
  add_foreign_key "route_buses", "buses"
  add_foreign_key "route_buses", "routes"
  add_foreign_key "route_segment_stats", "routes"
  add_foreign_key "route_segment_stats", "stops", column: "from_stop_id"
  add_foreign_key "route_segment_stats", "stops", column: "to_stop_id"
  add_foreign_key "routes", "areas"
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "stop_events", "buses"
  add_foreign_key "stop_events", "stops"
  add_foreign_key "stop_likes", "buses"
  add_foreign_key "stop_likes", "stops"
  add_foreign_key "stops", "routes"
  add_foreign_key "trips", "buses"
end
