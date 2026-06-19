class Route < ApplicationRecord
  belongs_to :area, counter_cache: true
  belongs_to :bus, optional: true
  has_many :stops, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :area_id }
  validates :headway_minutes, numericality: { greater_than: 0 }, allow_nil: true

  default_scope { order(:position, :name) }

  def region
    area.region
  end
end
