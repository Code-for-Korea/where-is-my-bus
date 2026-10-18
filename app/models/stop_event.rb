class StopEvent < ApplicationRecord
  belongs_to :bus
  belongs_to :stop

  validates :bus_id, :stop_id, :event_type, :occurred_at, :dedup_key, presence: true
  validates :dedup_key, uniqueness: true
end
