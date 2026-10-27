require "test_helper"

class TraccarGeofenceSyncTest < ActiveSupport::TestCase
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    TraccarGeofenceSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
    @stop = Stop.create!(name: "신규 정류장", lat: 37.5, lng: 127.0)
  end

  test "rectangle_wkt returns a closed polygon centered on the coordinates" do
    wkt = TraccarGeofenceSync.rectangle_wkt(lat: 37.5, lng: 127.0)

    points = wkt[/POLYGON\(\((.*)\)\)/, 1].split(", ").map { |p| p.split.map(&:to_f) }
    assert_equal 5, points.size
    assert_equal points.first, points.last
    assert_in_delta 37.5, points[0..3].sum { |lat, _| lat } / 4, 1e-9
    assert_in_delta 127.0, points[0..3].sum { |_, lng| lng } / 4, 1e-9
  end

  test "creates a geofence when stop has no traccar_geofence_id and does not link any group" do
    stub_request(:post, "http://traccar.test/api/geofences")
      .with(body: hash_including(name: @stop.name))
      .to_return(status: 200, body: { id: 21 }.to_json, headers: JSON_HEADERS)

    result = TraccarGeofenceSync.call(@stop)

    assert result.success
    assert_equal 21, @stop.reload.traccar_geofence_id
    assert_not_requested :post, "http://traccar.test/api/permissions"
  end

  test "updates the geofence when stop already has a traccar_geofence_id" do
    @stop.update!(traccar_geofence_id: 21)
    stub_request(:put, "http://traccar.test/api/geofences/21")
      .with(body: hash_including(id: 21, name: @stop.name))
      .to_return(status: 200, body: "", headers: {})

    assert TraccarGeofenceSync.call(@stop).success
  end

  test "returns a failure result without raising when the API call fails" do
    stub_request(:post, "http://traccar.test/api/geofences").to_return(status: 500, body: "boom")

    result = TraccarGeofenceSync.call(@stop)

    assert result.failure?
    assert_nil @stop.reload.traccar_geofence_id
  end

  test "destroy skips when stop has no traccar_geofence_id" do
    assert TraccarGeofenceSync.destroy(@stop).success
  end

  test "destroy deletes the geofence when stop has a traccar_geofence_id" do
    @stop.update!(traccar_geofence_id: 21)
    stub_request(:delete, "http://traccar.test/api/geofences/21").to_return(status: 204, body: "")

    assert TraccarGeofenceSync.destroy(@stop).success
  end

  test "destroy returns a failure result without raising when the API call fails" do
    @stop.update!(traccar_geofence_id: 21)
    stub_request(:delete, "http://traccar.test/api/geofences/21").to_return(status: 500, body: "boom")

    assert TraccarGeofenceSync.destroy(@stop).failure?
  end
end
