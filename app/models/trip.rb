class Trip < ApplicationRecord
  belongs_to :bus
  belongs_to :route
  has_many :stop_visits, dependent: :destroy

  validates :started_at, presence: true
  validate :bus_has_no_other_active_trip, on: :create

  scope :active, -> { where(ended_at: nil) }

  def active?
    ended_at.nil?
  end

  def finish!(at = Time.current)
    update!(ended_at: at)
  end

  private

  # 최종 방어선은 trips.bus_id의 부분 유니크 인덱스. 여기서는 사용자에게 읽을 수 있는 오류를 먼저 준다.
  def bus_has_no_other_active_trip
    return unless active? && bus && Trip.active.where(bus_id: bus_id).exists?

    errors.add(:bus, "에 이미 진행 중인 운행이 있습니다")
  end
end
