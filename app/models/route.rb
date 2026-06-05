class Route < ApplicationRecord
  # 버스 노선. 예: 35번 버스 (배차간격 1시간, 추천수 2,345)
  # Area 소속, 하위에 Stop(정류장)을 순서대로 가진다.

  belongs_to :area, counter_cache: true
  has_many :stops, -> { order(:position) }, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :area_id }
  validates :headway_minutes, numericality: { greater_than: 0 }, allow_nil: true

  default_scope { order(:position, :name) }

  def region
    area.region
  end
end
