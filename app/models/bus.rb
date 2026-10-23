class Bus < ApplicationRecord
  # 차량마다 배정된 노선 하나. 관리자가 배정하고, 운전자는 운행을 시작할 때 이 노선을 쓴다.
  belongs_to :route, optional: true
  has_many :trips, dependent: :restrict_with_error
  has_one :active_trip, -> { where(ended_at: nil) }, class_name: "Trip"

  validates :license_plate, presence: true, uniqueness: true
  validate :route_unchanged_during_trip, on: :update
  validates :pin,           presence: true, format: { with: /\A\d{4,6}\z/, message: "은 4~6자리 숫자여야 합니다" }, uniqueness: true
  validates :traccar_unique_id, presence: true, uniqueness: true
  validates :traccar_device_id, uniqueness: true, allow_nil: true

  before_validation :assign_traccar_unique_id, on: :create
  before_validation :assign_pin, on: :create

  scope :ordered, -> { order(:license_plate) }

  # 관리자가 노선에 차량을 배정할 때 보는 이름: 어느 노선에 배정돼 있는지 함께 보여준다.
  def assignment_label
    "#{license_plate} (#{route ? "현재: #{route.name}" : "미배정"})"
  end

  # PIN 유출 시 운영자가 즉시 무효화할 수 있도록 — 재발급하면 옛 PIN으로는 더 이상 register API가 안 먹힘.
  # pin_registered_at도 함께 초기화해서 새 PIN으로 다시 한 번 등록(기기분실/교체 포함)할 수 있게 한다.
  def regenerate_pin!
    update!(pin: generate_pin, pin_registered_at: nil)
  end

  private

  # 운행 중에 노선을 바꾸면 진행 중인 운행의 노선과 Traccar 그룹이 어긋나므로 운행이 끝난 뒤에만 바꿀 수 있다.
  def route_unchanged_during_trip
    return unless route_id_changed? && active_trip

    errors.add(:route, "은 운행 중에는 바꿀 수 없습니다")
  end

  # 운영자가 수동 입력하던 값을 자동 생성으로 대체 — 추측 불가능성 보장(driver_app/README.md #백엔드 리스트).
  def assign_traccar_unique_id
    return if traccar_unique_id.present?

    self.traccar_unique_id = loop do
      candidate = SecureRandom.hex(6)
      break candidate unless Bus.exists?(traccar_unique_id: candidate)
    end
  end

  def assign_pin
    self.pin = generate_pin if pin.blank?
  end

  def generate_pin
    loop do
      candidate = SecureRandom.random_number(1_000_000).to_s.rjust(6, "0")
      break candidate unless Bus.exists?(pin: candidate)
    end
  end
end
