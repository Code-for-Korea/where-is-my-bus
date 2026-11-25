require "net/http"
require "json"

module Demo
  # 운전자 앱 대신 버스 한 대가 노선을 한 바퀴 도는 것을 흉내낸다. 앱이 하는 일을 그대로 따른다:
  #   1) 운행 시작 API 호출 (노선은 차량에 배정된 노선)
  #   2) Traccar의 위치 수신 포트(OsmAnd 프로토콜)로 좌표를 계속 전송
  #   3) 운행 종료 API 호출
  # 정류장 Geofence는 30m 정사각형이므로 좌표 간격을 speed_kmh/3.6 미터(45km/h면 12.5m)로 유지해
  # 영역 안에 반드시 한 번은 들어가게 한다. 기본 간격 1초 기준 108km/h 미만이면 30m 반변을 넘지 않는다.
  # 위치 시각은 항상 앞으로만 간다 — Traccar는 과거 시각의 위치를 건너뛰어 이벤트가 사라진다.
  class BusSimulator
    APPROACH_METERS = 100.0
    METERS_PER_DEGREE = 111_320.0

    Point = Struct.new(:lat, :lng, :speed, :label, keyword_init: true)

    def initialize(device_id:, rails_url: "http://localhost:3000", osmand_url: "http://localhost:5055",
                   interval: 1.0, dwell: 6, settle: 3.0, speed_kmh: 45.0, laps: 1, pass_wait: nil, lap_gap: 0.0, start_stop: nil, out: $stdout)
      @device_id = device_id
      @rails_url = rails_url
      @osmand_url = osmand_url
      @interval = interval
      @dwell = dwell
      @settle = settle
      raise ArgumentError, "반복 횟수는 0 이상이어야 합니다 (0이면 중단할 때까지 계속)." if laps.negative?

      @laps = laps # 반복 횟수. 0이면 중단(Ctrl+C)할 때까지 계속 돈다
      @pass_wait = pass_wait || settle # 마지막 정류장을 떠난 뒤 운행을 끝내기 전까지 기다리는 시간 — 화면이 "지나갔습니다"를 보여 줄 시간
      @lap_gap = lap_gap # 바퀴 사이 쉬는 시간
      @start_stop = start_stop # 이 이름의 정류장부터 끝까지만 주행(nil이면 노선 전체). 응답에 정류장 id가 없어 이름으로만 지정한다
      @speed_kmh = speed_kmh
      @step_meters = speed_kmh / 3.6
      @out = out
      @last_timestamp = 0
    end

    def run
      info = fetch_info
      route = info["route"] ||
              raise(ArgumentError, "이 차량에는 배정된 노선이 없습니다. 관리자 화면에서 노선을 배정하세요.")
      route = route.merge("stops" => stops_from_start(route["stops"])) if @start_stop
      end_trip if info["activeTrip"]

      lap = 0
      loop do
        lap += 1
        @out.puts "== #{lap}번째 운행#{" (중단: Ctrl+C)" if @laps.zero? && lap == 1}" unless @laps == 1
        drive_once(route)
        break if @laps.positive? && lap >= @laps

        sleep @lap_gap
      end
    end

    private

    # 지정한 이름의 정류장부터 끝까지. 그 정류장 100m 앞에서 출발하는 것은 build_path가 그대로 처리한다.
    def stops_from_start(stops)
      index = stops.index { |stop| stop["name"] == @start_stop }
      raise ArgumentError, "시작 정류장 '#{@start_stop}'이(가) 노선에 없습니다 (노선의 정류장: #{stops.map { |s| s["name"] }.join(", ")})" unless index

      rest = stops.drop(index)
      raise ArgumentError, "마지막 정류장에서는 시작할 수 없습니다 (방향 계산에 정류장이 2개 이상 필요합니다): #{@start_stop}" if rest.size < 2

      @out.puts "시작 정류장: #{@start_stop} (이후 #{rest.size - 1}개 정류장)"
      rest
    end

    # 운행 하나: 시작 → 노선 주행 → (마지막 정류장 이탈 이벤트가 도착할 시간을 둔 뒤) 종료.
    def drive_once(route)
      begin
        start_trip(route) # 요청 도중 Ctrl+C가 와도 서버에 열린 운행이 남지 않도록 ensure 안에서 시작한다
        build_path(route["stops"]).each { |point| send_position(point) }
        sleep @pass_wait
      ensure
        end_trip
      end
    end

    def fetch_info
      get_json("/integrations/traccar/bus?deviceId=#{@device_id}")
    end

    def start_trip(route)
      response = post_json("/integrations/traccar/trips/start", deviceId: @device_id)
      raise "운행 시작 실패: #{response}" unless response["trip"]

      @out.puts "운행 시작: #{route["name"]} (운행 ##{response["trip"]["id"]})"
    end

    def end_trip
      response = post_json("/integrations/traccar/trips/end", deviceId: @device_id)
      @out.puts "운행 종료" if response["ended"]
    end

    # 첫 정류장 100m 앞에서 출발해 정류장을 차례로 지나고, 마지막 정류장을 80m 지나쳐 끝난다.
    # 정류장마다 dwell초 동안 멈춘다(속도 0).
    def build_path(stops)
      points = [ start_point(stops) ]
      stops.each do |stop|
        points.concat(interpolate(points.last, stop["lat"], stop["lng"]))
        (@dwell / @interval).ceil.times { points << Point.new(lat: stop["lat"], lng: stop["lng"], speed: 0, label: stop["name"]) }
      end
      points.concat(interpolate(points.last, *beyond(stops.last(2), 80.0)))
    end

    def start_point(stops)
      first, second = stops.first(2)
      lat, lng = move(first["lat"], first["lng"], *direction(second, first), APPROACH_METERS)
      Point.new(lat: lat, lng: lng, speed: (@speed_kmh / @interval).round(1))
    end

    # from에서 (lat, lng)까지 @step_meters 간격의 좌표들 (to 포함, from 제외).
    def interpolate(from, lat, lng)
      steps = [ (distance(from.lat, from.lng, lat, lng) / @step_meters).ceil, 1 ].max
      (1..steps).map do |i|
        ratio = i.to_f / steps
        Point.new(lat: from.lat + (lat - from.lat) * ratio, lng: from.lng + (lng - from.lng) * ratio, speed: (@speed_kmh / @interval).round(1))
      end
    end

    # 마지막 두 정류장의 진행 방향으로 meters만큼 더 간 지점.
    def beyond(last_two, meters)
      prev, last = last_two.size == 2 ? last_two : [ last_two.first, last_two.first ]
      move(last["lat"], last["lng"], *direction(prev, last), meters)
    end

    # from → to 방향의 단위 벡터 (미터 기준 dx, dy).
    def direction(from, to)
      dx = (to["lng"] - from["lng"]) * Math.cos(to["lat"] * Math::PI / 180) * METERS_PER_DEGREE
      dy = (to["lat"] - from["lat"]) * METERS_PER_DEGREE
      length = Math.hypot(dx, dy)
      length.zero? ? [ 0.0, 1.0 ] : [ dx / length, dy / length ]
    end

    def move(lat, lng, unit_dx, unit_dy, meters)
      [ lat + unit_dy * meters / METERS_PER_DEGREE,
        lng + unit_dx * meters / (METERS_PER_DEGREE * Math.cos(lat * Math::PI / 180)) ]
    end

    def distance(lat1, lng1, lat2, lng2)
      dx = (lng2 - lng1) * Math.cos(lat1 * Math::PI / 180) * METERS_PER_DEGREE
      dy = (lat2 - lat1) * METERS_PER_DEGREE
      Math.hypot(dx, dy)
    end

    def send_position(point)
      @last_timestamp = [ Time.now.to_i, @last_timestamp + 1 ].max
      query = URI.encode_www_form(id: @device_id, lat: point.lat.round(6), lon: point.lng.round(6),
                                  timestamp: @last_timestamp, speed: point.speed)
      Net::HTTP.get_response(URI("#{@osmand_url}/?#{query}"))
      announce_arrival(point.label)
      sleep @interval
    end

    # 정류장에 멈춰 있는 동안 같은 로그가 반복되지 않도록 도착한 순간에 한 번만 출력한다.
    def announce_arrival(label)
      return if label.nil? || label == @announced

      @announced = label
      @out.puts "  #{label} 도착"
    end

    def get_json(path)
      JSON.parse(Net::HTTP.get_response(URI("#{@rails_url}#{path}")).body)
    end

    def post_json(path, params)
      JSON.parse(Net::HTTP.post_form(URI("#{@rails_url}#{path}"), params.transform_values(&:to_s)).body)
    end
  end
end
