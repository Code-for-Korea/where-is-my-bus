require "test_helper"

class Admin::StopsControllerTest < ActionDispatch::IntegrationTest
  setup do
    stub_traccar_credentials(TraccarGeofenceSync)
    sign_in_as(users(:operator))
  end

  test "index lists stops with the routes that serve them" do
    get admin_stops_path

    assert_response :ok
    assert_select "td", text: stops(:hospital).name
    assert_select "td", text: "1번 노선, 2번 노선"
  end

  test "create registers the stop and its Traccar geofence" do
    stub_request(:post, "#{TRACCAR_API}/api/geofences")
      .with(body: hash_including(name: "신규 정류장"))
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: 88 }.to_json)

    assert_difference -> { Stop.count }, 1 do
      post admin_stops_path, params: { stop: { name: "신규 정류장", lat: "34.99", lng: "128.34" } }
    end

    stop = Stop.find_by!(name: "신규 정류장")
    assert_redirected_to admin_stop_path(stop)
    assert_equal 88, stop.traccar_geofence_id
  end

  test "create shows the Traccar failure and creates nothing" do
    stub_request(:post, "#{TRACCAR_API}/api/geofences").to_return(status: 500, body: "boom")

    assert_no_difference -> { Stop.count } do
      post admin_stops_path, params: { stop: { name: "신규 정류장", lat: "34.99", lng: "128.34" } }
    end

    assert_response :unprocessable_entity
    assert_select "li", text: /geofence 동기화 실패/
  end

  test "create rejects out-of-range coordinates without calling Traccar" do
    post admin_stops_path, params: { stop: { name: "신규 정류장", lat: "134.99", lng: "128.34" } }

    assert_response :unprocessable_entity
    assert_not_requested :post, "#{TRACCAR_API}/api/geofences"
  end

  test "update moves the geofence along with the stop" do
    stop = stops(:school)
    put = stub_request(:put, "#{TRACCAR_API}/api/geofences/#{stop.traccar_geofence_id}").to_return(status: 200, body: "")

    patch admin_stop_path(stop), params: { stop: { lat: "34.9825" } }

    assert_redirected_to admin_stop_path(stop)
    assert_requested put
    assert_in_delta 34.9825, stop.reload.lat.to_f, 1e-6
  end

  test "destroy is refused when the stop has visit records and leaves the geofence alone" do
    assert_no_difference -> { Stop.count } do
      delete admin_stop_path(stops(:terminal))
    end

    assert_redirected_to admin_stop_path(stops(:terminal))
    assert_match(/삭제할 수 없습니다/, flash[:alert])
    assert_not_requested :delete, %r{/api/geofences}
  end

  test "destroy removes an unvisited stop and deletes its geofence" do
    stop = stops(:school)
    stub_request(:delete, "#{TRACCAR_API}/api/geofences/#{stop.traccar_geofence_id}").to_return(status: 204, body: "")

    assert_difference -> { Stop.count }, -1 do
      delete admin_stop_path(stop)
    end

    assert_redirected_to admin_stops_path
  end
end
