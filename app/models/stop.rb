class Stop < ApplicationRecord
  has_many :route_stops, dependent: :destroy
  has_many :routes, through: :route_stops
  has_many :stop_visits, dependent: :restrict_with_error

  validates :name, presence: true
  validates :lat, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :lng, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :traccar_geofence_id, uniqueness: true, allow_nil: true

  # 관리자 지도에서 정류장도 없고 현재 위치도 얻지 못했을 때 처음 보여 줄 위치(고성).
  MAP_FALLBACK_CENTER = [ 34.9731, 128.3222 ].freeze

  scope :ordered, -> { order(:name) }

  # 등록된 정류장 좌표의 평균. 정류장이 없으면 nil.
  def self.center
    lat, lng = average(:lat), average(:lng)
    [ lat.to_f, lng.to_f ] if lat && lng
  end
end
