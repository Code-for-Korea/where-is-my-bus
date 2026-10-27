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

  def simulate
    Demo::BusSimulator.new(device_id: "dev1", rails_url: RAILS, osmand_url: OSMAND,
                           interval: 0.001, dwell: 0.002, settle: 0, out: StringIO.new).run
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
end
