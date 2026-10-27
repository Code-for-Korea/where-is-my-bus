require "test_helper"

class Admin::RouteStopsControllerTest < ActionDispatch::IntegrationTest
  setup do
    stub_traccar_credentials(TraccarRouteStopLink)
    sign_in_as(users(:operator))
  end

  test "create adds the stop to the route and links its geofence to the route's group" do
    route = routes(:one)
    link = stub_request(:post, "#{TRACCAR_API}/api/permissions")
      .with(body: { groupId: route.traccar_group_id, geofenceId: stops(:school).traccar_geofence_id }.to_json)
      .to_return(status: 204, body: "")

    assert_difference -> { route.route_stops.count }, 1 do
      post admin_route_route_stops_path(route), params: { stop_id: stops(:school).id, sequence: 4 }
    end

    assert_redirected_to admin_route_path(route)
    assert_requested link
  end

  test "create reports the Traccar failure and adds nothing" do
    stub_request(:post, "#{TRACCAR_API}/api/permissions").to_return(status: 500, body: "boom")

    assert_no_difference -> { RouteStop.count } do
      post admin_route_route_stops_path(routes(:one)), params: { stop_id: stops(:school).id, sequence: 4 }
    end

    assert_redirected_to admin_route_path(routes(:one))
    assert_match(/추가할 수 없습니다/, flash[:alert])
  end

  test "create rejects a duplicate sequence" do
    assert_no_difference -> { RouteStop.count } do
      post admin_route_route_stops_path(routes(:one)), params: { stop_id: stops(:school).id, sequence: 1 }
    end

    assert_match(/추가할 수 없습니다/, flash[:alert])
  end

  test "create rejects a missing stop" do
    assert_no_difference -> { RouteStop.count } do
      post admin_route_route_stops_path(routes(:one)), params: { sequence: 4 }
    end

    assert_match(/추가할 수 없습니다/, flash[:alert])
  end

  test "destroy removes the stop from the route and unlinks the geofence" do
    route_stop = route_stops(:two_school)
    unlink = stub_request(:delete, "#{TRACCAR_API}/api/permissions").to_return(status: 204, body: "")

    assert_difference -> { RouteStop.count }, -1 do
      delete admin_route_route_stop_path(route_stop.route, route_stop)
    end

    assert_redirected_to admin_route_path(route_stop.route)
    assert_requested unlink
  end
end
