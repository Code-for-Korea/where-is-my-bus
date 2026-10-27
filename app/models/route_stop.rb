class RouteStop < ApplicationRecord
  belongs_to :route
  belongs_to :stop

  validates :sequence, presence: true, numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :route_id }
  validates :stop_id, uniqueness: { scope: :route_id }
end
