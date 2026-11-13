require "test_helper"

class Admin::RoutesControllerTest < ActionDispatch::IntegrationTest
  setup do
    stub_traccar_credentials(TraccarGroupSync)
    sign_in_as(users(:operator))
  end

  test "index lists routes with their stop counts" do
    get admin_routes_path

    assert_response :ok
    assert_select "a", text: routes(:one).name
    assert_select "td", text: "3"
  end

  test "index shows each route's regions or an undecided label" do
    empty = Route.create!(name: "빈 노선")

    get admin_routes_path

    assert_select "tr", text: /#{routes(:one).name}.*경상남도 고성군/m
    assert_select "tr", text: /#{empty.name}.*지역 미정/m
    assert_select "td", text: "경상남도 고성군", count: 2
    assert_select "td", text: "지역 미정", count: 1
  end

  test "index query count does not grow with the number of routes" do
    add_routes = lambda do |count, tag|
      count.times do |i|
        route = Route.create!(name: "#{tag}노선#{i}")
        stop = Stop.create!(name: "#{tag}정류장#{i}", lat: 35, lng: 128, region: regions(:ulleung_eup))
        route.route_stops.create!(stop: stop, sequence: 1)
      end
    end

    add_routes.call(3, "가")
    few = count_queries { get admin_routes_path }
    add_routes.call(10, "나")
    many = count_queries { get admin_routes_path }

    assert_equal few, many
  end

  test "show displays the route's regions" do
    get admin_route_path(routes(:one))

    assert_select "[data-role=route-regions]", text: "경상남도 고성군"
  end

  test "show displays an undecided label when no stop has a region" do
    route = Route.create!(name: "빈 노선")

    get admin_route_path(route)

    assert_select "[data-role=route-regions]", text: "지역 미정"
  end

  test "show lists stops in sequence order and offers the stops not yet on the route" do
    get admin_route_path(routes(:one))

    assert_response :ok
    assert_select "ol li", count: 3
    assert_select "ol li:first-child", text: /고성터미널/
    assert_select "select[name=stop_id] option", text: stops(:school).name
    assert_select "select[name=stop_id] option", text: stops(:terminal).name, count: 0
  end

  test "create registers the route and its Traccar group" do
    stub_request(:post, "#{TRACCAR_API}/api/groups")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: 55 }.to_json)

    assert_difference -> { Route.count }, 1 do
      post admin_routes_path, params: { route: { name: "3번 노선" } }
    end

    route = Route.find_by!(name: "3번 노선")
    assert_redirected_to admin_route_path(route)
    assert_equal 55, route.traccar_group_id
  end

  test "create shows the Traccar failure and creates nothing" do
    stub_request(:post, "#{TRACCAR_API}/api/groups").to_return(status: 500, body: "boom")

    assert_no_difference -> { Route.count } do
      post admin_routes_path, params: { route: { name: "3번 노선" } }
    end

    assert_response :unprocessable_entity
    assert_select "li", text: /Traccar 노선 동기화 실패/
  end

  test "create shows validation errors for a duplicate name" do
    post admin_routes_path, params: { route: { name: routes(:one).name } }

    assert_response :unprocessable_entity
    assert_select ".bg-red-50"
    assert_not_requested :post, "#{TRACCAR_API}/api/groups"
  end

  test "update renames the route and its Traccar group" do
    route = routes(:one)
    stub_request(:put, "#{TRACCAR_API}/api/groups/#{route.traccar_group_id}").to_return(status: 200, body: "")

    patch admin_route_path(route), params: { route: { name: "새 이름" } }

    assert_redirected_to admin_route_path(route)
    assert_equal "새 이름", route.reload.name
  end

  test "destroy is refused with a reason when the route has trips" do
    assert_no_difference -> { Route.count } do
      delete admin_route_path(routes(:one))
    end

    assert_redirected_to admin_route_path(routes(:one))
    assert_match(/삭제할 수 없습니다/, flash[:alert])
  end

  test "destroy removes a route without trips and deletes its Traccar group" do
    route = Route.create!(name: "임시", traccar_group_id: 900)
    stub_request(:delete, "#{TRACCAR_API}/api/groups/900").to_return(status: 204, body: "")

    assert_difference -> { Route.count }, -1 do
      delete admin_route_path(route)
    end

    assert_redirected_to admin_routes_path
  end

  test "sync_group re-syncs the group" do
    route = routes(:one)
    put = stub_request(:put, "#{TRACCAR_API}/api/groups/#{route.traccar_group_id}").to_return(status: 200, body: "")

    post sync_group_admin_route_path(route)

    assert_redirected_to admin_route_path(route)
    assert_requested put
  end

  private

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
