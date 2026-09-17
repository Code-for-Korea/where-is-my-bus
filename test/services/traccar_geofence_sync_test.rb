require "test_helper"

class TraccarGeofenceSyncTest < ActiveSupport::TestCase
  setup do
    TraccarGeofenceSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
    TraccarGroupSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")

    @route = routes(:one)
    @route.update!(traccar_group_id: 7)
    @stop = Stop.create!(route: @route, name: "정류장1", sequence: 1, lat: 37.5, lng: 127.0)
  end

  test "skips when stop has no coordinates" do
    @stop.update_columns(lat: nil, lng: nil)

    result = TraccarGeofenceSync.call(@stop)

    assert result.success
    assert_not_requested :post, "http://traccar.test/api/geofences"
  end

  test "creates the route's group first when it is missing, then creates the geofence and links it to the group" do
    @route.update!(traccar_group_id: nil)
    stub_request(:post, "http://traccar.test/api/groups")
      .to_return(status: 200, body: { id: 55 }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:post, "http://traccar.test/api/geofences")
      .to_return(status: 200, body: { id: 21 }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:post, "http://traccar.test/api/permissions")
      .with(body: { groupId: 55, geofenceId: 21 }.to_json)
      .to_return(status: 200, body: "", headers: {})

    result = TraccarGeofenceSync.call(@stop)

    assert result.success
    assert_equal 55, @route.reload.traccar_group_id
    assert_equal 21, @stop.reload.traccar_geofence_id
  end

  test "returns the group sync failure result when group creation fails" do
    @route.update!(traccar_group_id: nil)
    stub_request(:post, "http://traccar.test/api/groups").to_return(status: 500, body: "boom")

    result = TraccarGeofenceSync.call(@stop)

    assert result.failure?
    assert_not_requested :post, "http://traccar.test/api/geofences"
  end

  test "creates a new geofence when stop has no traccar_geofence_id, then links it to the group" do
    stub_request(:post, "http://traccar.test/api/geofences")
      .with(body: hash_including(name: "stop-#{@stop.id}"))
      .to_return(status: 200, body: { id: 21 }.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:post, "http://traccar.test/api/permissions")
      .with(body: { groupId: 7, geofenceId: 21 }.to_json)
      .to_return(status: 200, body: "", headers: {})

    result = TraccarGeofenceSync.call(@stop)

    assert result.success
    assert_equal 21, @stop.reload.traccar_geofence_id
  end

  test "updates an existing geofence when stop already has a traccar_geofence_id" do
    @stop.update!(traccar_geofence_id: 21)
    stub_request(:put, "http://traccar.test/api/geofences/21")
      .with(body: hash_including(id: 21, name: "stop-#{@stop.id}"))
      .to_return(status: 200, body: "", headers: {})
    stub_request(:post, "http://traccar.test/api/permissions")
      .with(body: { groupId: 7, geofenceId: 21 }.to_json)
      .to_return(status: 200, body: "", headers: {})

    result = TraccarGeofenceSync.call(@stop)

    assert result.success
  end

  test "returns a failure result without raising when the API call fails" do
    stub_request(:post, "http://traccar.test/api/geofences").to_return(status: 500, body: "boom")

    result = TraccarGeofenceSync.call(@stop)

    assert result.failure?
  end

  test "destroy skips when stop has no traccar_geofence_id" do
    result = TraccarGeofenceSync.destroy(@stop)

    assert result.success
  end

  test "destroy deletes the geofence when stop has a traccar_geofence_id" do
    @stop.update!(traccar_geofence_id: 21)
    stub_request(:delete, "http://traccar.test/api/geofences/21").to_return(status: 204, body: "")

    result = TraccarGeofenceSync.destroy(@stop)

    assert result.success
  end

  test "destroy returns a failure result without raising when the API call fails" do
    @stop.update!(traccar_geofence_id: 21)
    stub_request(:delete, "http://traccar.test/api/geofences/21").to_return(status: 500, body: "boom")

    result = TraccarGeofenceSync.destroy(@stop)

    assert result.failure?
  end
end
