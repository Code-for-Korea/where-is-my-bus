module Admin
  module RegionsHelper
    SELECT_CLASS = "select-chevron w-full rounded-lg border border-gray-300 px-3 py-2 text-sm focus:border-indigo-500 focus:ring-indigo-500 disabled:bg-gray-100 disabled:text-gray-400".freeze

    # 레벨 번호에 붙이는 이름(한국 기준). 이 범위를 넘는 레벨은 "N단계"로 표시한다.
    LEVEL_LABELS = { 1 => "시도", 2 => "시군구", 3 => "읍면동", 4 => "리" }.freeze

    def region_level_label(level)
      LEVEL_LABELS.fetch(level, "#{level}단계")
    end

    # 지역 연쇄 선택의 칸들. 레벨마다 한 칸씩 항상 모두 그린다(한국 기준 시도·시군구·읍면동·리).
    # 칸의 선택지는 "그 칸보다 얕은 레벨 중 가장 가까이 고른 지역"의 활성 하위 지역 가운데 레벨이 같은 것이다.
    # 세종처럼 레벨이 건너뛰는 경우 건너뛴 칸은 선택지가 없어 비활성으로 남는다.
    # 반환: [{ level:, label:, options_html:, disabled: }, ...]
    def region_select_slots(region)
      chain = []
      current = region
      while current
        chain.unshift(current)
        current = current.parent
      end

      top = [ Region.maximum(:level).to_i, LEVEL_LABELS.keys.max ].max
      (1..top).map do |level|
        parent = chain.select { |r| r.level < level }.last
        selected = chain.find { |r| r.level == level }
        region_select_slot(level, parent, selected)
      end
    end

    STATUS_LABELS = { "active" => "활성", "inactive" => "비활성" }.freeze

    # 지금 적용 중인 필터. 칩 하나를 누르면 그 필터만 빠진 목록으로 간다.
    # 반환: [{ label:, path: }, ...]
    def region_filter_chips
      current = { region_id: @filter_region&.id, q: @query.presence, status: @status, with_stops: (1 if @with_stops) }.compact
      chips = []
      chips << [ "지역: #{@filter_region.full_name}", :region_id ] if @filter_region
      chips << [ "이름: #{@query}", :q ] if @query.present?
      chips << [ "상태: #{STATUS_LABELS[@status]}", :status ] if @status
      chips << [ "정류장이 있는 지역", :with_stops ] if @with_stops
      chips.map { |label, key| { label: label, path: admin_regions_path(current.except(key)) } }
    end

    private

    def region_select_slot(level, parent, selected)
      siblings = Region.where(parent_id: parent&.id, level: level)
      regions = siblings.where(active: true).or(siblings.where(id: selected&.id)).ordered
                        .includes(parent: { parent: { parent: :parent } }).to_a
      # 옵션마다 묻지 않도록 하위 지역이 있는 id를 한 번에 구한다.
      with_children = Region.active.where(parent_id: regions.map(&:id)).distinct.pluck(:parent_id).to_set

      options = regions.map do |region|
        [ region.active? ? region.name : "#{region.name} (비활성)", region.id, {
          "data-level" => region.level,
          "data-bounds" => region.bounds&.to_json.to_s,
          "data-has-children" => with_children.include?(region.id).to_s
        } ]
      end
      {
        level: level,
        label: region_level_label(level),
        options_html: options_for_select([ [ "선택", "" ] ] + options, selected&.id),
        disabled: regions.empty?
      }
    end
  end
end
