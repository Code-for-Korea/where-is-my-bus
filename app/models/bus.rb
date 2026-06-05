class Bus < ApplicationRecord
  # 차량. 번호판 + 운전자 인증용 PIN.
  # 운전자는 앱에서 지역/노선/번호판 선택 후 PIN으로 운행을 시작한다.
  # 차량은 운행지역(Area)에 소속되며, 운행 시점에 노선이 배정된다.

  belongs_to :area

  validates :license_plate, presence: true, uniqueness: { scope: :area_id }
  validates :pin, presence: true, format: { with: /\A\d{4,6}\z/, message: "은 4~6자리 숫자여야 합니다" }

  default_scope { order(:license_plate) }
end
