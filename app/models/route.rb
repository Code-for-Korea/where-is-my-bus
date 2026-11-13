class Route < ApplicationRecord
  has_many :route_stops, -> { order(:sequence) }, dependent: :destroy
  has_many :stops, through: :route_stops
  has_many :trips, dependent: :restrict_with_error
  has_many :buses, dependent: :restrict_with_error # 배정된 차량이 있으면 삭제할 수 없다

  validates :name, presence: true, uniqueness: true
  validates :traccar_group_id, uniqueness: true, allow_nil: true

  scope :ordered, -> { order(:name) }

  PRELOAD_ANCESTORS = { parent: { parent: { parent: :parent } } }.freeze

  # 노선의 지역은 저장하지 않고, 노선에 서는 정류장들의 지역(중복 없이)에서 파생한다.
  # 지역이 없는 정류장은 건너뛴다.
  def regions
    Region.where(id: stops.where.not(region_id: nil).select(:region_id)).ordered
  end

  # 여러 노선의 지역을 쿼리 2번으로 모은다. { route_id => [Region, ...] } (Region.ordered 순서, 지역 없으면 빈 배열)
  def self.regions_by_route(routes)
    ids = routes.map(&:id)
    region_ids_by_route = RouteStop.joins(:stop).where(route_id: ids).where.not(stops: { region_id: nil })
                                   .distinct.pluck(:route_id, "stops.region_id").group_by(&:first)
    regions = Region.where(id: region_ids_by_route.values.flatten(1).map(&:last).uniq)
                    .includes(PRELOAD_ANCESTORS).ordered.index_by(&:id)

    ids.index_with do |id|
      (region_ids_by_route[id] || []).map { |_, region_id| regions[region_id] }.sort_by { |r| [ r.level, r.name ] }
    end
  end
end
