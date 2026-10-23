require "test_helper"

# 승객 화면은 로그인 없이 쓴다: 정류장 선택 → (노선 선택) → 버스 위치.
class PassengerFlowTest < ActionDispatch::IntegrationTest
  test "home lists stops that are on a route, with their routes" do
    Stop.create!(name: "외딴 정류장", lat: 35.0, lng: 128.0)

    get root_path

    assert_response :ok
    assert_select "li[data-filter-target=item]", count: Stop.joins(:route_stops).distinct.count
    assert_select "li", text: /고성병원/
    assert_select "li", text: /1번 노선 · 2번 노선/
    assert_select "li", text: /외딴 정류장/, count: 0
  end

  test "a stop served by several routes asks which route and shows how many buses run" do
    get stop_path(stops(:hospital))

    assert_response :ok
    assert_select "a[href=?]", stop_route_arrivals_path(stops(:hospital), routes(:one)), text: /1번 노선.*운행 중 1대/m
    assert_select "a[href=?]", stop_route_arrivals_path(stops(:hospital), routes(:two)), text: /운행 중인 버스 없음/
  end

  test "a stop served by one route goes straight to the bus positions" do
    get stop_path(stops(:school))

    assert_redirected_to stop_route_arrivals_path(stops(:school), routes(:two))
  end

  test "shows how far the bus is from my stop" do
    get stop_route_arrivals_path(stops(:hospital), routes(:one))

    assert_response :ok
    assert_select "span", text: "다음 정류장이 내 정류장"
    assert_select "p", text: "고성시장 정차 중"
    assert_select "[data-controller=refresh][data-refresh-url-value=?]", stop_route_buses_path(stops(:hospital), routes(:one))
  end

  test "tells me when the bus is stopped at my stop" do
    get stop_route_arrivals_path(stops(:market), routes(:one))

    assert_select "span", text: "내 정류장에 정차 중"
  end

  test "tells me when no bus is running on the route" do
    get stop_route_arrivals_path(stops(:school), routes(:two))

    assert_select "div", text: /운행 중인 버스가 없습니다/
  end

  test "the refresh endpoint returns only the fragment without the page layout" do
    get stop_route_buses_path(stops(:hospital), routes(:one))

    assert_response :ok
    assert_no_match(/<html/, response.body)
    assert_match(/다음 정류장이 내 정류장/, response.body)
  end

  test "a route that does not serve the stop is not found" do
    get stop_route_arrivals_path(stops(:school), routes(:one))

    assert_response :not_found
  end

  test "an unknown stop is not found" do
    get stop_path(0)

    assert_response :not_found
  end
end
