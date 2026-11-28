require "test_helper"

class Demo::BusSimulatorTest < ActiveSupport::TestCase
  RAILS = "http://rails.test".freeze
  OSMAND = "http://osmand.test".freeze
  HALF_SIDE_METERS = 15.0 # TraccarGeofenceSync의 30m 정사각형 한 변의 절반
  STOPS = [
    { "name" => "A", "lat" => 34.9731, "lng" => 128.3222 },
    { "name" => "B", "lat" => 34.9751, "lng" => 128.3246 }
  ].freeze

  setup do
    @positions = []
    stub_request(:get, %r{#{RAILS}/integrations/traccar/bus})
      .to_return(body: { busNumber: "1", activeTrip: nil, route: { id: 1, name: "시험 노선", stops: STOPS } }.to_json)
    @start = stub_request(:post, "#{RAILS}/integrations/traccar/trips/start").to_return(body: { trip: { id: 9 } }.to_json)
    @finish = stub_request(:post, "#{RAILS}/integrations/traccar/trips/end").to_return(body: { ended: true }.to_json)
    stub_request(:get, %r{#{OSMAND}/\?}).with { |req| @positions << URI.decode_www_form(req.uri.query).to_h && true }
                                         .to_return(status: 200)
  end

  def simulate(**options)
    Demo::BusSimulator.new(device_id: "dev1", rails_url: RAILS, osmand_url: OSMAND,
                           interval: 0.001, dwell: 0.002, settle: 0, out: StringIO.new, **options).run
  end

  def positions
    @positions.map { |p| { lat: p["lat"].to_f, lng: p["lon"].to_f, time: p["timestamp"].to_i, speed: p["speed"].to_f } }
  end

  def meters_between(a, b)
    dy = (a[:lat] - b["lat"]) * 111_320.0
    dx = (a[:lng] - b["lng"]) * 111_320.0 * Math.cos(b["lat"] * Math::PI / 180)
    [ dx.abs, dy.abs ]
  end

  def inside_geofence?(point, stop)
    dx, dy = meters_between(point, stop)
    dx <= HALF_SIDE_METERS && dy <= HALF_SIDE_METERS
  end

  test "starts the trip, drives, and ends the trip" do
    simulate

    assert_requested @start, times: 1
    assert_requested @finish, times: 1
    assert_requested :get, %r{#{OSMAND}/\?id=dev1&}, at_least_times: 10
  end

  test "laps만큼 운행을 반복하고 매번 시작과 종료를 호출한다" do
    simulate(laps: 3)

    assert_requested @start, times: 3
    assert_requested @finish, times: 3
  end

  test "반복해도 위치 시각은 계속 앞으로만 간다" do
    simulate(laps: 2)

    assert_equal positions.map { |p| p[:time] }.sort, positions.map { |p| p[:time] }
    assert_equal positions.map { |p| p[:time] }.uniq.size, positions.size
  end

  test "pass_wait 동안 마지막 정류장을 떠난 상태로 운행을 유지한 뒤 종료한다" do
    waits = []
    sim = Demo::BusSimulator.new(device_id: "dev1", rails_url: RAILS, osmand_url: OSMAND,
                                 interval: 0.001, dwell: 0.002, settle: 0, pass_wait: 0.05, out: StringIO.new)
    sim.define_singleton_method(:sleep) { |seconds| waits << seconds; super(0) }
    sim.run

    assert_includes waits, 0.05
    assert_requested @finish, times: 1
  end

  test "every stop's geofence is entered at least once, and the first position is outside all of them" do
    simulate

    STOPS.each do |stop|
      assert positions.any? { |p| inside_geofence?(p, stop) }, "no position inside the geofence of #{stop["name"]}"
    end
    assert STOPS.none? { |stop| inside_geofence?(positions.first, stop) }, "the bus must start outside every geofence"
  end

  test "the bus stops (speed 0) inside each stop's geofence" do
    simulate

    STOPS.each do |stop|
      assert positions.any? { |p| p[:speed].zero? && inside_geofence?(p, stop) }, "no dwell at #{stop["name"]}"
    end
  end

  test "timestamps only ever move forward, because Traccar skips positions from the past" do
    simulate

    times = positions.map { |p| p[:time] }
    assert_equal times.sort.uniq, times
  end

  test "the stops are visited in route order" do
    simulate

    first_inside = STOPS.map { |stop| positions.index { |p| inside_geofence?(p, stop) } }
    assert_equal first_inside.sort, first_inside
  end

  test "ends the trip even when sending a position fails" do
    stub_request(:get, %r{#{OSMAND}/\?}).to_raise(Errno::ECONNREFUSED)

    assert_raises(Errno::ECONNREFUSED) { simulate }
    assert_requested @finish, times: 1
  end

  test "ends a leftover trip before starting a new one" do
    stub_request(:get, %r{#{RAILS}/integrations/traccar/bus})
      .to_return(body: { busNumber: "1", activeTrip: { id: 3 }, route: { id: 1, name: "시험 노선", stops: STOPS } }.to_json)

    simulate

    assert_requested @finish, times: 2
  end

  test "refuses to drive when the bus has no assigned route" do
    stub_request(:get, %r{#{RAILS}/integrations/traccar/bus})
      .to_return(body: { busNumber: "1", activeTrip: nil, route: nil }.to_json)

    error = assert_raises(ArgumentError) { simulate }

    assert_match(/배정된 노선이 없습니다/, error.message)
    assert_not_requested :post, "#{RAILS}/integrations/traccar/trips/start"
  end

  test "starts the trip without sending a route — the server uses the assigned one" do
    simulate

    assert_requested :post, "#{RAILS}/integrations/traccar/trips/start", body: { "deviceId" => "dev1" }
  end

  # 시작 정류장 옵션: 3개 정류장 노선(서→동으로 곧게 놓인다)
  THREE = [
    { "name" => "A", "lat" => 34.9731, "lng" => 128.3222 },
    { "name" => "B", "lat" => 34.9731, "lng" => 128.3262 },
    { "name" => "C", "lat" => 34.9731, "lng" => 128.3302 }
  ].freeze

  def stub_route(stops)
    stub_request(:get, %r{#{RAILS}/integrations/traccar/bus})
      .to_return(body: { busNumber: "1", activeTrip: nil, route: { id: 1, name: "시험 노선", stops: stops } }.to_json)
  end

  def simulate_with_log(**options)
    out = StringIO.new
    Demo::BusSimulator.new(device_id: "dev1", rails_url: RAILS, osmand_url: OSMAND,
                           interval: 0.001, dwell: 0.002, settle: 0, out: out, **options).run
    out.string
  end

  test "start_stop을 주면 그 정류장부터 도착 로그가 나오고 앞 정류장은 지나지 않는다" do
    stub_route(THREE)

    log = simulate_with_log(start_stop: "B")

    assert_match(/시작 정류장: B \(이후 1개 정류장\)/, log)
    assert_no_match(/A 도착/, log)
    assert_match(/B 도착/, log)
    assert_match(/C 도착/, log)
    assert positions.none? { |p| inside_geofence?(p, THREE[0]) }, "앞 정류장 지오펜스에 들어가면 안 된다"
  end

  test "start_stop 정류장 약 100m 앞(전 정류장 쪽)에서 출발한다" do
    stub_route(THREE)

    simulate(start_stop: "B")

    first = positions.first
    dx, dy = meters_between(first, THREE[1])
    assert_in_delta 100.0, dx, 1.0
    assert_in_delta 0.0, dy, 1.0
    assert_operator first[:lng], :<, THREE[1]["lng"], "전 정류장(서쪽) 쪽이어야 한다"
    assert THREE.none? { |stop| inside_geofence?(first, stop) }
  end

  test "laps=2: 첫 바퀴만 start_stop부터, 둘째 바퀴는 첫 정류장 100m 앞에서 전체 노선" do
    stub_route(THREE)

    log = simulate_with_log(start_stop: "B", laps: 2)

    first_lap, second_lap = log.split(/^== 2번째 운행.*$/)
    assert_no_match(/A 도착/, first_lap)
    %w[B C].each { |name| assert_match(/#{name} 도착/, first_lap) }
    assert_match(/전체 노선/, log)
    %w[A B C].each { |name| assert_match(/#{name} 도착/, second_lap) }
    second_start = positions.find { |p| meters_between(p, THREE[0]).first.round(1) == 100.0 && p[:lng] < THREE[0]["lng"] }
    assert second_start, "둘째 바퀴는 A 100m 앞(서쪽)에서 출발해야 한다"
    assert positions.any? { |p| inside_geofence?(p, THREE[0]) }
    assert_requested @start, times: 2
    assert_requested @finish, times: 2
  end

  test "laps=1이면 start_stop부터 종점까지 한 번만 달리고 끝난다" do
    stub_route(THREE)

    log = simulate_with_log(start_stop: "B", laps: 1)

    assert_no_match(/A 도착/, log)
    assert_no_match(/번째 운행/, log)
    assert_requested @start, times: 1
    assert positions.none? { |p| inside_geofence?(p, THREE[0]) }
  end

  test "start_stop 없이 laps=2면 모든 바퀴가 전체 노선이고 전체 노선 안내가 없다" do
    stub_route(THREE)

    log = simulate_with_log(laps: 2)

    assert_no_match(/전체 노선|시작 정류장/, log)
    assert_equal 2, log.scan(/A 도착/).size
  end

  test "start_stop을 주지 않으면 노선 전체를 돈다" do
    stub_route(THREE)

    log = simulate_with_log

    assert_no_match(/시작 정류장/, log)
    %w[A B C].each { |name| assert_match(/#{name} 도착/, log) }
  end

  test "노선에 없는 start_stop은 정류장 목록과 함께 ArgumentError" do
    stub_route(THREE)

    error = assert_raises(ArgumentError) { simulate(start_stop: "없는정류장") }

    assert_match(/없는정류장/, error.message)
    assert_match(/A, B, C/, error.message)
    assert_not_requested :post, "#{RAILS}/integrations/traccar/trips/start"
  end

  test "마지막 정류장은 start_stop으로 지정할 수 없다" do
    stub_route(THREE)

    error = assert_raises(ArgumentError) { simulate(start_stop: "C") }

    assert_match(/마지막 정류장에서는 시작할 수 없습니다/, error.message)
    assert_not_requested :post, "#{RAILS}/integrations/traccar/trips/start"
  end
end
