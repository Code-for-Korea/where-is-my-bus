require "test_helper"

class RouteStopRegistrationTest < ActiveSupport::TestCase
  setup do
    TraccarRouteStopLink.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
    @route = routes(:two)
    @stop = stops(:market)
    @ids = { groupId: @route.traccar_group_id, geofenceId: @stop.traccar_geofence_id }
  end

  test "create adds the stop to the route and links the geofence to the route's group" do
    link = stub_request(:post, "http://traccar.test/api/permissions").with(body: @ids.to_json).to_return(status: 204, body: "")

    result = RouteStopRegistration.create(route: @route, stop: @stop, sequence: 4)

    assert result.success?
    assert RouteStop.exists?(route: @route, stop: @stop, sequence: 4)
    assert_requested link
  end

  test "create rolls back when Traccar fails" do
    stub_request(:post, "http://traccar.test/api/permissions").to_return(status: 500, body: "boom")

    assert_no_difference -> { RouteStop.count } do
      assert RouteStopRegistration.create(route: @route, stop: @stop, sequence: 4).failure?
    end
  end

  test "create rejects a duplicate sequence without calling Traccar" do
    result = RouteStopRegistration.create(route: @route, stop: @stop, sequence: 1)

    assert result.failure?
    assert_not_requested :post, "http://traccar.test/api/permissions"
  end

  test "create fails when the stop has no geofence yet" do
    @stop.update!(traccar_geofence_id: nil)

    assert_no_difference -> { RouteStop.count } do
      assert RouteStopRegistration.create(route: @route, stop: @stop, sequence: 4).failure?
    end
  end

  test "destroy removes the stop from the route and unlinks the geofence" do
    route_stop = route_stops(:two_school)
    unlink = stub_request(:delete, "http://traccar.test/api/permissions")
      .with(body: { groupId: route_stop.route.traccar_group_id, geofenceId: route_stop.stop.traccar_geofence_id }.to_json)
      .to_return(status: 204, body: "")

    result = RouteStopRegistration.destroy(route_stop)

    assert result.success?
    assert_not RouteStop.exists?(route_stop.id)
    assert_requested unlink
  end

  test "destroy keeps the route stop when Traccar fails" do
    route_stop = route_stops(:two_school)
    stub_request(:delete, "http://traccar.test/api/permissions").to_return(status: 500, body: "boom")

    assert RouteStopRegistration.destroy(route_stop).failure?
    assert RouteStop.exists?(route_stop.id)
  end
end
