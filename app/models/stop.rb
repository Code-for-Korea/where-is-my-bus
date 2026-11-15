class Stop < ApplicationRecord
  has_many :route_stops, dependent: :destroy
  has_many :routes, through: :route_stops
  has_many :stop_visits, dependent: :restrict_with_error
  belongs_to :region, optional: true

  validates :name, presence: true
  validates :lat, presence: true, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :lng, presence: true, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }
  validates :traccar_geofence_id, uniqueness: true, allow_nil: true
  validate :region_must_be_valid, if: :region_required?
  validate :region_must_be_deep_enough, if: -> { region }

  # 정류장 지역의 최소 깊이(2 = 시도 + 시군구). 시도만 고르면 범위가 너무 넓다.
  MIN_REGION_LEVEL = 2

  scope :ordered, -> { order(:name) }

  # 새 정류장 폼에 미리 채울 지역: 가장 최근에 등록한, 지금도 고를 수 있는 지역.
  def self.last_registered_region
    Region.active.where(level: MIN_REGION_LEVEL..).joins(:stops).order("stops.id DESC").first
  end

  private

  # 1차 배포 단계: 지역이 없는 기존 정류장도 저장돼야 하므로 새로 만들 때, 또는 region_id를 바꿀 때만 검증한다.
  # 2차 배포에서 무조건 필수로 바꾸고 NOT NULL로 만든다.
  def region_required?
    new_record? || region_id_changed?
  end

  def region_must_be_valid
    if region.nil?
      errors.add(:region, :blank)
    elsif !region.active?
      errors.add(:region, "폐지된 지역이라 선택할 수 없습니다")
    end
  end

  def region_must_be_deep_enough
    errors.add(:region, "시군구까지 선택해 주세요") if region.level < MIN_REGION_LEVEL
  end
end
