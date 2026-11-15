class Region < ApplicationRecord
  belongs_to :parent, class_name: "Region", optional: true
  has_many :children, class_name: "Region", foreign_key: :parent_id, inverse_of: :parent, dependent: :restrict_with_error
  has_many :stops, dependent: :restrict_with_error

  BOUNDS_ATTRIBUTES = %i[south west north east].freeze

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true
  validates :kind, presence: true
  validates :level, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validate :parent_code_must_exist
  validate :parent_level_must_be_lower
  validate :level_must_stay_below_children
  validate :bounds_must_be_complete_and_ordered

  scope :roots, -> { where(parent_id: nil) }
  scope :active, -> { where(active: true) }
  # 지역 자신과 그 아래 모든 지역. 부모 참조를 재귀로 따라가므로 코드 규칙에 기대지 않는다.
  scope :within, ->(region) {
    where("regions.id IN (WITH RECURSIVE tree(id) AS (SELECT id FROM regions WHERE id = :id " \
          "UNION ALL SELECT r.id FROM regions r JOIN tree ON r.parent_id = tree.id) SELECT id FROM tree)", id: region.id)
  }
  scope :with_stops, -> { where(id: Stop.where.not(region_id: nil).select(:region_id)) }
  scope :ordered, -> { order(:level, :name) }

  # 활성 최상위 지역들의 영역을 모두 포함하는 [[남, 서], [북, 동]]. 영역이 있는 지역이 없으면 nil.
  def self.country_bounds
    all_bounds = roots.active.filter_map(&:bounds)
    return if all_bounds.empty?

    [ [ all_bounds.map { |b| b[0][0] }.min, all_bounds.map { |b| b[0][1] }.min ],
      [ all_bounds.map { |b| b[1][0] }.max, all_bounds.map { |b| b[1][1] }.max ] ]
  end

  # [[남, 서], [북, 동]]. 자기 영역이 없으면 가장 가까운 상위 지역의 것을 쓴다. 없으면 nil.
  def bounds
    own_bounds || parent&.bounds
  end

  # [[남, 서], [북, 동]]. 상위 지역 것을 빌리지 않고 자기 영역만 본다. 없으면 nil.
  def own_bounds
    [ [ south.to_f, west.to_f ], [ north.to_f, east.to_f ] ] if own_bounds?
  end

  # 조상 이름부터 자기 이름까지 공백으로 이은 이름. 예: "경상북도 울릉군 울릉읍"
  def full_name
    [ parent&.full_name, name ].compact.join(" ")
  end

  # 폼에서 JS 없이 상위 지역을 고르기 위한 가상 속성. 코드가 비어 있으면 최상위가 된다.
  def parent_code
    @unknown_parent_code || parent&.code
  end

  def parent_code=(code)
    code = code.to_s.strip
    @unknown_parent_code = nil
    if code.blank?
      self.parent = nil
    elsif (found = Region.find_by(code: code))
      self.parent = found
    else
      @unknown_parent_code = code
    end
  end

  private

  def parent_code_must_exist
    errors.add(:parent_code, :invalid, message: "해당하는 지역이 없습니다") if @unknown_parent_code
  end

  def level_must_stay_below_children
    return unless persisted? && level_changed? && level.present?

    lowest_child_level = children.minimum(:level)
    return if lowest_child_level.nil? || level < lowest_child_level

    errors.add(:level, :invalid, message: "하위 지역보다 낮아야 합니다")
  end

  def own_bounds?
    BOUNDS_ATTRIBUTES.all? { |attr| self[attr].present? }
  end

  def parent_level_must_be_lower
    return if parent.nil? || level.blank?

    errors.add(:parent, "의 레벨이 이 지역보다 낮아야 합니다") unless parent.level < level
  end

  # 날짜 변경선(경도 ±180)을 넘는 지역은 지원하지 않는다(서 <= 동).
  def bounds_must_be_complete_and_ordered
    values = BOUNDS_ATTRIBUTES.map { |attr| self[attr] }
    return if values.all?(&:blank?)

    if values.any?(&:blank?)
      errors.add(:base, "영역(남·서·북·동)은 모두 입력하거나 모두 비워야 합니다")
      return
    end

    errors.add(:south, "위도는 -90~90 사이여야 합니다") unless south.between?(-90, 90)
    errors.add(:north, "위도는 -90~90 사이여야 합니다") unless north.between?(-90, 90)
    errors.add(:west, "경도는 -180~180 사이여야 합니다") unless west.between?(-180, 180)
    errors.add(:east, "경도는 -180~180 사이여야 합니다") unless east.between?(-180, 180)
    errors.add(:south, "북쪽보다 클 수 없습니다") if south > north
    errors.add(:west, "동쪽보다 클 수 없습니다") if west > east
  end
end
