class CreateRouteSegmentStats < ActiveRecord::Migration[8.1]
  def change
    create_table :route_segment_stats do |t|
      t.references :route, null: false, foreign_key: true
      t.references :from_stop, null: false, foreign_key: { to_table: :stops }
      t.references :to_stop, null: false, foreign_key: { to_table: :stops }
      t.integer :hour_of_day, null: false
      t.date :date, null: false
      t.float :avg_seconds, null: false
      t.integer :samples_count, null: false, default: 0

      t.timestamps
    end

    add_index :route_segment_stats, [ :route_id, :from_stop_id, :to_stop_id, :hour_of_day, :date ],
              name: "index_route_segment_stats_on_segment_and_hour_and_date", unique: true
  end
end
