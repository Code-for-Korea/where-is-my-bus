class Stop < ApplicationRecord
  # 정류장. 예: 욕지도 정류장 4번
  # Route 소속, position 순서대로 노선을 구성한다. 좌표는 운전자 앱에서 크라우드소싱으로 등록된다.

  belongs_to :route, counter_cache: true

  validates :name, presence: true
  validates :latitude,  numericality: { greater_than_or_equal_to: -90,  less_than_or_equal_to: 90 },  allow_nil: true
  validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true

  default_scope { order(:position) }

  def coordinates?
    latitude.present? && longitude.present?
  end
end
