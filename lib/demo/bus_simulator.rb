require "net/http"
require "json"

module Demo
  # 운전자 앱 대신 버스 한 대가 노선을 한 바퀴 도는 것을 흉내낸다. 앱이 하는 일을 그대로 따른다:
  #   1) 운행 시작 API 호출 (노선은 차량에 배정된 노선)
  #   2) Traccar의 위치 수신 포트(OsmAnd 프로토콜)로 좌표를 계속 전송
  #   3) 운행 종료 API 호출
  # 정류장 Geofence는 30m 정사각형이므로 좌표를 STEP_METERS(15m) 간격으로 보내 영역 안에 반드시 한 번은 들어가게 한다.
  # 위치 시각은 항상 앞으로만 간다 — Traccar는 과거 시각의 위치를 건너뛰어 이벤트가 사라진다.
  class BusSimulator
    STEP_METERS = 15.0
    APPROACH_METERS = 100.0
    METERS_PER_DEGREE = 111_320.0

    Point = Struct.new(:lat, :lng, :speed, :label, keyword_init: true)

    def initialize(device_id:, rails_url: "http://localhost:3000", osmand_url: "http://localhost:5055",
                   interval: 1.0, dwell: 6, settle: 3.0, out: $stdout)
      @device_id = device_id
      @rails_url = rails_url
      @osmand_url = osmand_url
      @interval = interval
      @dwell = dwell
      @settle = settle
      @out = out
      @last_timestamp = 0
    end

    def run
      info = fetch_info
      route = info["route"] ||
              raise(ArgumentError, "이 차량에는 배정된 노선이 없습니다. 관리자 화면에서 노선을 배정하세요.")
      end_trip if info["activeTrip"]
      start_trip(route)
      begin
        build_path(route["stops"]).each { |point| send_position(point) }
        sleep @settle # 마지막 정류장의 이탈 이벤트가 Rails에 도착할 시간을 준 뒤 종료한다
      ensure
        end_trip
      end
    end

    private

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
      Point.new(lat: lat, lng: lng, speed: 10)
    end

    # from에서 (lat, lng)까지 STEP_METERS 간격의 좌표들 (to 포함, from 제외).
    def interpolate(from, lat, lng)
      steps = [ (distance(from.lat, from.lng, lat, lng) / STEP_METERS).ceil, 1 ].max
      (1..steps).map do |i|
        ratio = i.to_f / steps
        Point.new(lat: from.lat + (lat - from.lat) * ratio, lng: from.lng + (lng - from.lng) * ratio, speed: 10)
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
