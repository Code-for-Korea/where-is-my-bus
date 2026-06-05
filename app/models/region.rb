class Region < ApplicationRecord
  # 광역 행정구역 (시·도). 예: 전라남도, 경상남도
  # 하위 계층: Region → Area → Route → Stop

  has_many :areas, dependent: :destroy

  validates :name, presence: true, uniqueness: true

  default_scope { order(:position, :name) }
end
