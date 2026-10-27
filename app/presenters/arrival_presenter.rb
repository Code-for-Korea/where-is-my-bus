# 도착 화면(파란 패널)에 보여줄 문구와 노선 진행 바 위치를 RouteBusStatuses 결과로 만든다.
# 첫 화면 렌더링과 5초 폴링 JSON이 같은 값을 쓰도록 한 곳에서 계산한다.
#
# 원래 화면의 큰 글씨는 "약 N분 후 도착예정"(ETA)이었다. ETA가 없으므로 같은 자리에
# "N정거장 전에 있습니다" 등 위치 문구를 보여주고, 진행 바는 남은 정류장 수로 움직인다.
class ArrivalPresenter
  # 진행 바(%) — 남은 정류장 수별 고정 점: 3정거장 이상 3, 2정거장 15, 1정거장 30, 도착 90.
  BAR_BY_STOPS_LEFT = { 0 => 90, 1 => 30, 2 => 15 }.freeze
  BAR_FAR = 3
  BAR_PASSED = 96
  BAR_IDLE = 50

  def initialize(statuses:, route_stops:, stop:)
    @statuses = statuses
    @route_stops = route_stops
    @stop = stop
  end

  attr_reader :statuses

  def primary
    @statuses.first
  end

  # 큰 글씨 위의 한 줄: 버스가 마지막으로 있던 정류장.
  def small
    status = primary
    return "" unless status && %i[approaching passed].include?(status.kind)

    key = status.at_last_stop ? "arrivals.status.at_stop" : "arrivals.status.left_stop"
    I18n.t(key, stop: status.last_stop.name)
  end

  # 큰 글씨 두 줄. 줄바꿈 위치를 유지하려고 배열로 돌려준다.
  def big_lines
    case primary&.kind
    when :arriving then lines("arrived")
    when :approaching then [ I18n.t("arrivals.status.stops_left_line1", count: primary.stops_left), I18n.t("arrivals.status.stops_left_line2") ]
    when :unknown then lines("unknown")
    when :passed then lines("passed")
    else lines("no_bus")
    end
  end

  def bar_pct
    status = primary
    case status&.kind
    when :arriving then BAR_BY_STOPS_LEFT.fetch(0)
    when :approaching then approaching_pct(status)
    when :passed then BAR_PASSED
    else BAR_IDLE
    end
  end

  # 위치를 모르거나 이미 지나갔으면 버스 아이콘을 흐리게 보여준다.
  def dim?
    !%i[arriving approaching].include?(primary&.kind)
  end

  # 두 번째 이후 버스들 한 줄 요약.
  def others
    @statuses.drop(1).map { |status| "#{bus_label(status.bus)} · #{short(status)}" }
  end

  # 자세히보기 모달: 노선의 정류장 순서와, 각 정류장에 있는(또는 방금 떠난) 버스.
  def timeline
    @route_stops.map do |route_stop|
      here = @statuses.select { |status| status.last_stop&.id == route_stop.stop_id }
      { name: route_stop.stop.name, mine: route_stop.stop_id == @stop.id, buses: here.map { |status| bus_label(status.bus) } }
    end
  end

  # 5초 폴링 응답. 문구는 클라이언트가 textContent로만 넣는다.
  def to_h
    { small: small, big: big_lines, barPct: bar_pct, dim: dim?, others: others }
  end

  private

  def lines(key)
    [ I18n.t("arrivals.status.#{key}_line1"), I18n.t("arrivals.status.#{key}_line2") ]
  end

  # 정류장에서 떠난 직후는 다음 점까지 절반쯤 간 위치에 둬서 움직임이 보이게 한다.
  def approaching_pct(status)
    here = position(status.stops_left)
    return here if status.at_last_stop

    (here + (position(status.stops_left - 1) - here) / 2.0).round
  end

  def position(stops_left)
    BAR_BY_STOPS_LEFT.fetch(stops_left, BAR_FAR)
  end

  def short(status)
    case status.kind
    when :arriving then I18n.t("arrivals.status.short_arriving")
    when :approaching then I18n.t("arrivals.status.short_stops_left", count: status.stops_left)
    when :passed then I18n.t("arrivals.status.short_passed")
    else I18n.t("arrivals.status.short_unknown")
    end
  end

  def bus_label(bus)
    bus.bus_number.presence || bus.license_plate
  end
end
