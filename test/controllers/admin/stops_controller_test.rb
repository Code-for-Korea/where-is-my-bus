require "test_helper"

module Admin
  class StopsControllerTest < ActionDispatch::IntegrationTest
    setup do
      TraccarGeofenceSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
      sign_in_as(users(:operator))
      @route = routes(:one)
      @route.update!(traccar_group_id: 42)
    end

    test "create succeeds and calls the geofence creation API" do
      stub_request(:post, "http://traccar.test/api/geofences")
        .to_return(status: 200, body: { id: 7 }.to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:post, "http://traccar.test/api/permissions").to_return(status: 200, body: "")

      assert_difference "Stop.count", 1 do
        post admin_stops_path, params: { stop: { route_id: @route.id, name: "새 정류장", sequence: 1, lat: 35.1, lng: 128.1 } }
      end

      stop = Stop.order(:id).last
      assert_redirected_to admin_stops_path(route_id: @route.id)
      assert_equal 7, stop.reload.traccar_geofence_id
      assert_nil flash[:alert]
    end

    test "create rolls back and does not save the stop when the geofence API fails" do
      stub_request(:post, "http://traccar.test/api/geofences").to_return(status: 500, body: "boom")

      assert_no_difference "Stop.count" do
        post admin_stops_path, params: { stop: { route_id: @route.id, name: "새 정류장", sequence: 1, lat: 35.1, lng: 128.1 } }
      end

      assert_response :unprocessable_entity
      assert_match(/Traccar 연동 실패/, response.body)
    end

    test "update succeeds and calls the geofence update API" do
      stop = Stop.create!(route: @route, name: "정류장", sequence: 1, lat: 35.1, lng: 128.1, traccar_geofence_id: 7)
      stub_request(:put, "http://traccar.test/api/geofences/7").to_return(status: 200, body: "")
      stub_request(:post, "http://traccar.test/api/permissions").to_return(status: 200, body: "")

      patch admin_stop_path(stop), params: { stop: { name: "정류장 수정" } }

      assert_redirected_to admin_stops_path(route_id: @route.id)
      assert_requested :put, "http://traccar.test/api/geofences/7"
      assert_equal "정류장 수정", stop.reload.name
      assert_nil flash[:alert]
    end

    test "update rolls back to the previous state when the geofence API fails" do
      stop = Stop.create!(route: @route, name: "정류장", sequence: 1, lat: 35.1, lng: 128.1, traccar_geofence_id: 7)
      stub_request(:put, "http://traccar.test/api/geofences/7").to_return(status: 500, body: "boom")

      patch admin_stop_path(stop), params: { stop: { name: "정류장 수정" } }

      assert_response :unprocessable_entity
      assert_equal "정류장", stop.reload.name
      assert_match(/Traccar 연동 실패/, response.body)
    end

    test "destroy calls the geofence deletion API" do
      stop = Stop.create!(route: @route, name: "정류장", sequence: 1, lat: 35.1, lng: 128.1, traccar_geofence_id: 7)
      stub_request(:delete, "http://traccar.test/api/geofences/7").to_return(status: 204, body: "")

      assert_difference "Stop.count", -1 do
        delete admin_stop_path(stop)
      end

      assert_redirected_to admin_stops_path(route_id: @route.id)
      assert_requested :delete, "http://traccar.test/api/geofences/7"
    end

    test "destroy keeps the stop when the geofence deletion API fails" do
      stop = Stop.create!(route: @route, name: "정류장", sequence: 1, lat: 35.1, lng: 128.1, traccar_geofence_id: 7)
      stub_request(:delete, "http://traccar.test/api/geofences/7").to_return(status: 500, body: "boom")

      assert_no_difference "Stop.count" do
        delete admin_stop_path(stop)
      end

      assert_redirected_to admin_stop_path(stop)
      assert_match(/삭제할 수 없습니다/, flash[:alert])
    end

    test "sync_geofence succeeds and shows a notice" do
      stop = Stop.create!(route: @route, name: "정류장", sequence: 1, lat: 35.1, lng: 128.1, traccar_geofence_id: 7)
      stub_request(:put, "http://traccar.test/api/geofences/7").to_return(status: 200, body: "")
      stub_request(:post, "http://traccar.test/api/permissions").to_return(status: 200, body: "")

      post sync_geofence_admin_stop_path(stop)

      assert_redirected_to admin_stop_path(stop)
      assert_match(/성공/, flash[:notice])
    end

    test "sync_geofence failure shows a flash alert" do
      stop = Stop.create!(route: @route, name: "정류장", sequence: 1, lat: 35.1, lng: 128.1, traccar_geofence_id: 7)
      stub_request(:put, "http://traccar.test/api/geofences/7").to_return(status: 500, body: "boom")

      post sync_geofence_admin_stop_path(stop)

      assert_redirected_to admin_stop_path(stop)
      assert_match(/geofence 동기화 실패/, flash[:alert])
    end
  end
end
