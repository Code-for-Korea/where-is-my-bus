class RouteBus < ApplicationRecord
  belongs_to :route
  belongs_to :bus

  validates :bus_id, uniqueness: { scope: :route_id }
end
