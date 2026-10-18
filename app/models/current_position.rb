class CurrentPosition < ApplicationRecord
  belongs_to :bus

  validates :bus_id, :lat, :lng, :recorded_at, :received_at, presence: true
end
