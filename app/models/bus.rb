class Bus < ApplicationRecord
  belongs_to :area
  has_many :route_buses, dependent: :destroy
  has_many :routes,      through: :route_buses
  has_many :trips,       dependent: :destroy
  has_many :pin_codes,   dependent: :destroy

  enum :status, { active: "active", inactive: "inactive", deleted: "deleted" }

  validates :license_plate, presence: true, uniqueness: { scope: :area_id }
  validates :pin,           presence: true, format: { with: /\A\d{4,6}\z/, message: "은 4~6자리 숫자여야 합니다" }, uniqueness: true
  validates :traccar_unique_id, uniqueness: true, allow_nil: true

  before_validation :assign_traccar_unique_id, on: :create
  before_validation :assign_pin, on: :create

  default_scope { order(:license_plate) }

  def region
    area.region
  end

  def display_number
    return license_plate unless bus_number.present?
    I18n.locale == :ko ? bus_number : bus_number.gsub("번", "").strip
  end

  # PIN 유출 시 운영자가 즉시 무효화할 수 있도록 — 재발급하면 옛 PIN으로는 더 이상 register API가 안 먹힘.
  def regenerate_pin!
    update!(pin: generate_pin)
  end

  private

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
