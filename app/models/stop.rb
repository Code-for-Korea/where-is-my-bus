class Stop < ApplicationRecord
  has_many :route_stops, dependent: :destroy
  has_many :routes, through: :route_stops
  has_many :stop_visits, dependent: :restrict_with_error

  validates :name, presence: true
  validates :lat, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :lng, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :traccar_geofence_id, uniqueness: true, allow_nil: true

  scope :ordered, -> { order(:name) }
end
