class Route < ApplicationRecord
  has_many :route_stops, -> { order(:sequence) }, dependent: :destroy
  has_many :stops, through: :route_stops
  has_many :trips, dependent: :restrict_with_error
  has_many :buses, dependent: :restrict_with_error # 배정된 차량이 있으면 삭제할 수 없다

  validates :name, presence: true, uniqueness: true
  validates :traccar_group_id, uniqueness: true, allow_nil: true

  scope :ordered, -> { order(:name) }
end
