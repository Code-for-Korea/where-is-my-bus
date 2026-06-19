class GpsLog < ApplicationRecord
  belongs_to :trip

  validates :lat, :lng, :recorded_at, presence: true
end
