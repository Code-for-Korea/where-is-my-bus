class RouteSegmentStat < ApplicationRecord
  belongs_to :route
  belongs_to :from_stop, class_name: "Stop"
  belongs_to :to_stop, class_name: "Stop"

  validates :route_id, :from_stop_id, :to_stop_id, :hour_of_day, :date, :avg_seconds, :samples_count, presence: true
  validates :hour_of_day, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 23 }
end
