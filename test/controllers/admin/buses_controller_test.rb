require "test_helper"

module Admin
  class BusesControllerTest < ActionDispatch::IntegrationTest
    setup do
      TraccarDeviceSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
      sign_in_as(users(:operator))
      @area = areas(:one)
    end

    test "create succeeds and calls the device creation API" do
      stub_request(:post, "http://traccar.test/api/devices")
        .to_return(status: 200, body: { id: 99 }.to_json, headers: { "Content-Type" => "application/json" })

      assert_difference "Bus.count", 1 do
        post admin_buses_path, params: { bus: { area_id: @area.id, license_plate: "새차량0001" } }
      end

      bus = Bus.find_by!(license_plate: "새차량0001")
      assert_redirected_to admin_bus_path(bus)
      assert_equal 99, bus.reload.traccar_device_id
      assert_nil flash[:alert]
    end

    test "create rolls back and does not save the bus when the device API fails" do
      stub_request(:post, "http://traccar.test/api/devices").to_return(status: 500, body: "boom")

      assert_no_difference "Bus.count" do
        post admin_buses_path, params: { bus: { area_id: @area.id, license_plate: "새차량0001" } }
      end

      assert_response :unprocessable_entity
      assert_match(/Traccar 연동 실패/, response.body)
    end

    test "update succeeds and calls the device update API" do
      bus = buses(:one)
      bus.update_columns(traccar_device_id: 99)
      stub_request(:put, "http://traccar.test/api/devices/99").to_return(status: 200, body: "")

      patch admin_bus_path(bus), params: { bus: { bus_number: "9번" } }

      assert_redirected_to admin_bus_path(bus)
      assert_equal "9번", bus.reload.bus_number
      assert_nil flash[:alert]
    end

    test "update rolls back to the previous state when the device API fails" do
      bus = buses(:one)
      bus.update_columns(traccar_device_id: 99)
      stub_request(:put, "http://traccar.test/api/devices/99").to_return(status: 500, body: "boom")

      patch admin_bus_path(bus), params: { bus: { bus_number: "9번" } }

      assert_response :unprocessable_entity
      assert_not_equal "9번", bus.reload.bus_number
      assert_match(/Traccar 연동 실패/, response.body)
    end

    test "destroy calls the device deletion API" do
      bus = buses(:one)
      bus.update_columns(traccar_device_id: 99)
      stub_request(:delete, "http://traccar.test/api/devices/99").to_return(status: 204, body: "")

      assert_difference "Bus.count", -1 do
        delete admin_bus_path(bus)
      end

      assert_redirected_to admin_buses_path
    end

    test "destroy keeps the bus when the device deletion API fails" do
      bus = buses(:one)
      bus.update_columns(traccar_device_id: 99)
      stub_request(:delete, "http://traccar.test/api/devices/99").to_return(status: 500, body: "boom")

      assert_no_difference "Bus.count" do
        delete admin_bus_path(bus)
      end

      assert_redirected_to admin_bus_path(bus)
      assert_match(/삭제할 수 없습니다/, flash[:alert])
    end

    test "sync_device succeeds and shows a notice" do
      bus = buses(:one)
      bus.update_columns(traccar_device_id: 99)
      stub_request(:put, "http://traccar.test/api/devices/99").to_return(status: 200, body: "")

      post sync_device_admin_bus_path(bus)

      assert_redirected_to admin_bus_path(bus)
      assert_match(/성공/, flash[:notice])
    end

    test "sync_device failure shows a flash alert" do
      bus = buses(:one)
      bus.update_columns(traccar_device_id: 99)
      stub_request(:put, "http://traccar.test/api/devices/99").to_return(status: 500, body: "boom")

      post sync_device_admin_bus_path(bus)

      assert_redirected_to admin_bus_path(bus)
      assert_match(/device 동기화 실패/, flash[:alert])
    end
  end
end
