require "test_helper"

# 승객 화면은 로그인 없이 쓴다: 홈 → (정류장·노선 선택 시트) → 도착 화면. origin/main의 디자인을 따른다.
# 픽스처: 1번 노선은 터미널 → 시장 → 병원, 버스 one이 운행 중이고 지금 시장에 정차 중이다.
class PassengerFlowTest < ActionDispatch::IntegrationTest
  test "home shows the original hero, headline and a button that opens the selector sheet" do
    get root_path

    assert_response :ok
    assert_select "img[src^='/bus_hero.png']"
    assert_select "h1", text: "내 버스는 언제올까?"
    assert_select "button[data-action='click->bus-selector#open']", text: "버스는 지금 어디?"
    assert_select "a[href=?]", about_path
    assert_select "img[src='/codeforkorea.webp']"
  end

  test "the selector sheet lists the stops and routes that have service" do
    Stop.create!(name: "외딴 정류장", lat: 35.0, lng: 128.0)

    get root_path

    assert_select "select[data-bus-selector-target=stop] option", count: 1 + Stop.joins(:route_stops).distinct.count
    assert_select "select[data-bus-selector-target=stop] option", text: /외딴 정류장/, count: 0
    assert_select "select[data-bus-selector-target=route] option[data-stops]", count: Route.count
    assert_select "button[data-action='click->bus-selector#confirm']", text: "버스 노선 확인"
  end

  test "home shows a disabled button when there is nothing to show yet" do
    RouteStop.delete_all

    get root_path

    assert_select "button[disabled]", text: "서비스 준비 중"
  end

  test "the about page keeps its copy and lists the routes with service" do
    get about_path

    assert_response :ok
    assert_select "h1", text: "내 버스는 언제올까?"
    assert_select "li", text: /1번 노선/
    assert_select "button[data-action='click->bus-selector#open']", text: "버스 노선 확인"
  end

  test "a stop served by several routes asks which route and shows how many buses run" do
    get stop_path(stops(:hospital))

    assert_response :ok
    assert_select "h2", text: "고성병원"
    assert_select "a[href=?]", stop_route_arrivals_path(stops(:hospital), routes(:one)), text: /1번 노선.*운행 중 1대/m
    assert_select "a[href=?]", stop_route_arrivals_path(stops(:hospital), routes(:two)), text: /운행 중인 버스 없음/
  end

  test "a stop served by one route goes straight to the bus positions" do
    get stop_path(stops(:school))

    assert_redirected_to stop_route_arrivals_path(stops(:school), routes(:two))
  end

  test "arrival screen uses the grey stop panel and the blue position panel" do
    get stop_route_arrivals_path(stops(:hospital), routes(:one))

    assert_response :ok
    assert_select ".bg-gray-50 h2", text: "고성병원"
    assert_select ".bg-gray-50 span.text-indigo-600", text: "1번 노선"
    assert_select ".bg-blue-600 p", text: "1번 노선 버스는 지금 어디?"
    assert_select "[data-arrival-polling-target=small]", text: "고성시장 정차 중"
    assert_select "[data-arrival-polling-target=big]", text: "1정거장 전에있습니다."
    assert_select "[data-arrival-polling-target=busMarker][style*='left: 30%']"
  end

  test "arrival screen says the bus has arrived when it is stopped at my stop" do
    get stop_route_arrivals_path(stops(:market), routes(:one))

    assert_select "[data-arrival-polling-target=big]", text: "지금 정류장에도착했습니다."
    assert_select "[data-arrival-polling-target=busMarker][style*='left: 90%']"
  end

  test "arrival screen says no bus is running and dims the bus icon" do
    get stop_route_arrivals_path(stops(:school), routes(:two))

    assert_select "[data-arrival-polling-target=big]", text: "운행 중인 버스가없습니다."
    assert_select "[data-arrival-polling-target=busMarker].opacity-40"
  end

  test "the route dropdown opens the selector sheet with the current stop and route chosen" do
    get stop_route_arrivals_path(stops(:hospital), routes(:one))

    assert_select "button[data-action='click->bus-selector#open']", text: /1번 노선/
    assert_select "select[data-bus-selector-target=stop] option[selected]", text: /고성병원/
    assert_select "select[data-bus-selector-target=route] option[selected]", text: /1번 노선/
    assert_select "a[data-turbo-frame=detail-modal][href=?]", stop_route_detail_path(stops(:hospital), routes(:one)), text: "자세히보기"
  end

  test "the status endpoint returns what the screen needs to refresh itself" do
    get stop_route_status_path(stops(:hospital), routes(:one))

    assert_response :ok
    assert_equal({ "small" => "고성시장 정차 중", "big" => [ "1정거장 전에", "있습니다." ], "barPct" => 30,
                   "dim" => false, "others" => [] }, response.parsed_body)
  end

  test "the detail modal lists the stops in order, marks my stop and where the bus is" do
    get stop_route_detail_path(stops(:hospital), routes(:one))

    assert_response :ok
    assert_select "turbo-frame#detail-modal"
    assert_select "span", text: "1번 노선"
    assert_select "p", text: /운행 중 1대 \| 총 3개 정류장/
    assert_select "span.font-bold.text-gray-900", text: "고성병원"
    assert_select "span.bg-indigo-600", text: "여기", count: 1
    assert_select "span.text-indigo-500", text: "1번"
  end

  test "a route that does not serve the stop is not found on every screen" do
    [ stop_route_arrivals_path(stops(:school), routes(:one)),
      stop_route_status_path(stops(:school), routes(:one)),
      stop_route_detail_path(stops(:school), routes(:one)) ].each do |path|
      get path
      assert_response :not_found, path
    end
  end

  test "an unknown stop is not found" do
    get stop_path(0)

    assert_response :not_found
  end
end
