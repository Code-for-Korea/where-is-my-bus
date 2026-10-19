require "test_helper"
require "nokogiri"

class MapControllerTest < ActionDispatch::IntegrationTest
  setup do
    @route = routes(:one)
    @bus = buses(:one)
    @bus.update!(traccar_unique_id: "map-test-device")
    RouteBus.find_or_create_by!(route: @route, bus: @bus)
  end

  test "노선 지도 페이지를 렌더링한다" do
    get route_map_path(id: @route.id)

    assert_response :ok
    assert_select "[data-controller='map']"
    assert_select "[data-map-provider-value='google']"
  end

  test "Google Maps API 키가 있으면 스크립트와 콜백 정의를 로드한다" do
    ENV["GOOGLE_MAPS_API_KEY"] = "test-key-123"

    get route_map_path(id: @route.id)

    assert_response :ok
    assert_includes response.body, "window.initMapProvider"
    assert_includes response.body, "maps.googleapis.com/maps/api/js?key=test-key-123"
    refute_includes response.body, "Google Maps API 키가 설정되지 않았습니다"
  ensure
    ENV.delete("GOOGLE_MAPS_API_KEY")
  end

  test "data-* 속성이 올바른 JSON으로 직렬화된다" do
    get route_map_path(id: @route.id)

    assert_response :ok
    stops = parsed_map_data["data-map-stops-value"]
    assert_instance_of Array, stops
    stops.each do |stop|
      assert stop.key?("id")
      assert stop.key?("name")
      assert_instance_of Float, stop["lat"], "lat는 숫자여야 한다"
      assert_instance_of Float, stop["lng"], "lng는 숫자여야 한다"
    end
  end

  test "좌표가 없는 정류장은 제외하고 좌표가 있는 정류장은 포함한다" do
    stops_with_coords = @route.stops.select(&:coordinates?)
    get route_map_path(id: @route.id)

    assert_response :ok
    stops = parsed_map_data["data-map-stops-value"]
    assert_equal stops_with_coords.map(&:id).sort, stops.map { |s| s["id"] }.sort
  end

  test "GPS가 있는 버스는 마커 데이터에 숫자 좌표로 포함된다" do
    trip = trips(:one_active)
    GpsLog.create!(trip: trip, lat: 35.100000, lng: 128.100000, recorded_at: 1.minute.ago)
    PositionIngestor.call({ id: @bus.traccar_unique_id, lat: 35.100000, lon: 128.100000, timestamp: 1.minute.ago.to_i }, source: :osmand)

    get route_map_path(id: @route.id)

    assert_response :ok
    buses = parsed_map_data["data-map-buses-value"]
    bus = buses.find { |b| b["id"] == @bus.id }
    assert_not_nil bus, "GPS가 있는 버스는 마커 데이터에 포함되어야 한다"
    assert_equal "35.1", bus["lat"].to_s
    assert_instance_of Float, bus["lat"], "lat는 숫자여야 한다"
    assert_instance_of Float, bus["lng"], "lng는 숫자여야 한다"
  end

  test "존재하지 않는 노선은 404를 반환한다" do
    get route_map_path(id: 999_999)

    assert_response :not_found
  end

  private

  def parsed_map_data
    @parsed_map_data ||= begin
      doc = Nokogiri::HTML(response.body)
      element = doc.at_css("[data-controller='map']")
      raise "지도 컨트롤러 요소를 찾을 수 없습니다" unless element

      {
        "data-map-stops-value" => JSON.parse(element["data-map-stops-value"]),
        "data-map-buses-value" => JSON.parse(element["data-map-buses-value"]),
        "data-map-center-value" => JSON.parse(element["data-map-center-value"])
      }
    end
  end
end
