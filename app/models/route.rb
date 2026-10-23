class Route < ApplicationRecord
  has_many :route_stops, -> { order(:sequence) }, dependent: :destroy
  has_many :stops, through: :route_stops
  has_many :trips, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
  validates :traccar_group_id, uniqueness: true, allow_nil: true

  scope :ordered, -> { order(:name) }
end
