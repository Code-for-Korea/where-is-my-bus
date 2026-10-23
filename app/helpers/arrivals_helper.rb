module ArrivalsHelper
  def bus_label(bus)
    bus.bus_number.presence || bus.license_plate
  end

  def status_headline(status)
    case status.kind
    when :arriving then "내 정류장에 정차 중"
    when :approaching then status.stops_left == 1 ? "다음 정류장이 내 정류장" : "#{status.stops_left}개 정류장 남음"
    when :passed then "이미 지나갔어요"
    else "위치 확인 중"
    end
  end

  def status_detail(status)
    case status.kind
    when :approaching, :passed then "#{status.last_stop.name} #{status.at_last_stop ? "정차 중" : "출발"}"
    when :unknown then "아직 정류장 도착 신호가 없어요"
    end
  end

  def status_card_classes(status)
    case status.kind
    when :arriving then "bg-green-50 border-green-200"
    when :approaching then "bg-indigo-50 border-indigo-200"
    when :passed then "bg-gray-50 border-gray-200 opacity-60"
    else "bg-gray-50 border-gray-200"
    end
  end
end
