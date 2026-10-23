require "test_helper"

class TraccarRouteStopLinkTest < ActiveSupport::TestCase
  setup do
    TraccarRouteStopLink.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
    @route_stop = route_stops(:one_market)
    @ids = { groupId: @route_stop.route.traccar_group_id, geofenceId: @route_stop.stop.traccar_geofence_id }
  end

  test "link permits the route's group to receive the stop's geofence events" do
    stub = stub_request(:post, "http://traccar.test/api/permissions")
      .with(body: @ids.to_json)
      .to_return(status: 204, body: "")

    result = TraccarRouteStopLink.link(@route_stop)

    assert result.success
    assert_requested stub
  end

  test "link fails without calling Traccar when the route has no group yet" do
    @route_stop.route.update!(traccar_group_id: nil)

    result = TraccarRouteStopLink.link(@route_stop)

    assert result.failure?
    assert_not_requested :post, "http://traccar.test/api/permissions"
  end

  test "link fails without calling Traccar when the stop has no geofence yet" do
    @route_stop.stop.update!(traccar_geofence_id: nil)

    assert TraccarRouteStopLink.link(@route_stop).failure?
    assert_not_requested :post, "http://traccar.test/api/permissions"
  end

  test "link returns a failure result without raising when the API call fails" do
    stub_request(:post, "http://traccar.test/api/permissions").to_return(status: 500, body: "boom")

    assert TraccarRouteStopLink.link(@route_stop).failure?
  end

  test "unlink removes the permission" do
    stub = stub_request(:delete, "http://traccar.test/api/permissions")
      .with(body: @ids.to_json)
      .to_return(status: 204, body: "")

    assert TraccarRouteStopLink.unlink(@route_stop).success
    assert_requested stub
  end

  test "unlink skips when there is nothing linked in Traccar" do
    @route_stop.stop.update!(traccar_geofence_id: nil)

    assert TraccarRouteStopLink.unlink(@route_stop).success
    assert_not_requested :delete, "http://traccar.test/api/permissions"
  end

  test "unlink returns a failure result without raising when the API call fails" do
    stub_request(:delete, "http://traccar.test/api/permissions").to_return(status: 500, body: "boom")

    assert TraccarRouteStopLink.unlink(@route_stop).failure?
  end
end
