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
    stub_credentials(api_key: "test-key-123") do
      get route_map_path(id: @route.id)

      assert_response :ok
      assert_includes response.body, "window.initMapProvider"
      assert_includes response.body, "maps.googleapis.com/maps/api/js?key=test-key-123"
      refute_includes response.body, "Google Maps API 키가 설정되지 않았습니다"
    end
  end

  test "credentials의 키를 ENV보다 우선 사용한다" do
    ENV["GOOGLE_MAPS_API_KEY"] = "from-env"
    stub_credentials(api_key: "from-credentials") do
      assert_equal "from-credentials", helper_with_google_key
    end
  ensure
    ENV.delete("GOOGLE_MAPS_API_KEY")
  end

  test "credentials에 키가 없으면 ENV를 사용한다" do
    ENV["GOOGLE_MAPS_API_KEY"] = "from-env"
    stub_credentials(api_key: nil) do
      assert_equal "from-env", helper_with_google_key
    end
  ensure
    ENV.delete("GOOGLE_MAPS_API_KEY")
  end

  private

  def helper_with_google_key
    Object.new.extend(MapHelper).google_maps_api_key
  end

  private

  # 테스트용 credentials 스왑 — 실제 encrypted credentials는 테스트에서 편집할 수 없다
  def stub_credentials(api_key:)
    Rails.application.singleton_class.alias_method(:__original_credentials, :credentials)
    Rails.application.define_singleton_method(:credentials) do
      { google_maps: { api_key: api_key } }
    end
    yield
  ensure
    Rails.application.singleton_class.send(:remove_method, :credentials)
    Rails.application.singleton_class.send(:alias_method, :credentials, :__original_credentials)
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
