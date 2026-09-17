class Route < ApplicationRecord
  belongs_to :area, counter_cache: true
  has_many :stops, dependent: :destroy
  has_many :route_buses, dependent: :destroy
  has_many :buses, through: :route_buses

  validates :name, presence: true, uniqueness: { scope: :area_id }
  validates :headway_minutes, numericality: { greater_than: 0 }, allow_nil: true

  default_scope { order(:position, :name) }

  def region
    area.region
  end
end
