require "test_helper"

class StopRegistrationTest < ActiveSupport::TestCase
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    TraccarGeofenceSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
  end

  test "create saves the stop and creates its Traccar geofence" do
    stub_request(:post, "http://traccar.test/api/geofences")
      .with(body: hash_including(name: "신규 정류장"))
      .to_return(status: 200, body: { id: 88 }.to_json, headers: JSON_HEADERS)

    result = StopRegistration.create(name: "신규 정류장", lat: 34.99, lng: 128.34)

    assert result.success?
    assert_equal 88, result.record.reload.traccar_geofence_id
  end

  test "create rolls back the stop when Traccar fails" do
    stub_request(:post, "http://traccar.test/api/geofences").to_return(status: 500, body: "boom")

    assert_no_difference -> { Stop.count } do
      result = StopRegistration.create(name: "신규 정류장", lat: 34.99, lng: 128.34)

      assert result.failure?
    end
  end

  test "create rejects invalid coordinates without calling Traccar" do
    result = StopRegistration.create(name: "신규 정류장", lat: 134.99, lng: 128.34)

    assert result.failure?
    assert_not_requested :post, "http://traccar.test/api/geofences"
  end

  test "update moves the geofence along with the stop" do
    stop = stops(:school)
    put = stub_request(:put, "http://traccar.test/api/geofences/#{stop.traccar_geofence_id}")
      .with(body: hash_including(name: "고성고"))
      .to_return(status: 200, body: "")

    result = StopRegistration.update(stop, name: "고성고")

    assert result.success?
    assert_requested put
  end

  test "destroy removes the stop and deletes its Traccar geofence" do
    stop = stops(:school)
    delete = stub_request(:delete, "http://traccar.test/api/geofences/#{stop.traccar_geofence_id}").to_return(status: 204, body: "")

    result = StopRegistration.destroy(stop)

    assert result.success?
    assert_not Stop.exists?(stop.id)
    assert_requested delete
  end

  test "destroy leaves the Traccar geofence alone when the stop has visit records" do
    result = StopRegistration.destroy(stops(:terminal))

    assert result.failure?
    assert Stop.exists?(stops(:terminal).id)
    assert_not_requested :delete, %r{traccar.test/api/geofences}
  end

  test "destroy keeps the stop when Traccar deletion fails" do
    stop = stops(:school)
    stub_request(:delete, "http://traccar.test/api/geofences/#{stop.traccar_geofence_id}").to_return(status: 500, body: "boom")

    result = StopRegistration.destroy(stop)

    assert result.failure?
    assert Stop.exists?(stop.id)
    assert RouteStop.exists?(route: routes(:two), stop: stop)
  end
end
