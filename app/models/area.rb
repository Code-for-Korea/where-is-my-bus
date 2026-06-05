class Area < ApplicationRecord
  # 운행지역 (시·군 + 세부지역). 예: 통영시 욕지도
  # Region 소속, 하위에 Route(노선)와 Bus(차량)를 가진다.

  belongs_to :region, counter_cache: true
  has_many :routes, dependent: :destroy
  has_many :buses, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :region_id }

  default_scope { order(:position, :name) }

  def full_name
    "#{region.name} #{name}"
  end
end
