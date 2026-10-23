require "test_helper"

class Admin::BusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    stub_traccar_credentials(TraccarDeviceSync)
    sign_in_as(users(:operator))
  end

  test "index shows which buses are running and which routes they run" do
    get admin_buses_path

    assert_response :ok
    assert_select "td", text: "1번 노선 운행 중"
    assert_select "td", text: "운행 안 함"
  end

  test "show displays the pin, registration state and the running route" do
    get admin_bus_path(buses(:one))

    assert_response :ok
    assert_select ".font-mono", text: buses(:one).pin
    assert_select "a", text: "1번 노선"
    assert_select "span", text: /미등록/
  end

  test "create registers the bus and its Traccar device with a generated pin" do
    stub_request(:post, "#{TRACCAR_API}/api/devices")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: 66 }.to_json)

    assert_difference -> { Bus.count }, 1 do
      post admin_buses_path, params: { bus: { license_plate: "경남70가0001", bus_number: "3번" } }
    end

    bus = Bus.find_by!(license_plate: "경남70가0001")
    assert_redirected_to admin_bus_path(bus)
    assert_equal 66, bus.traccar_device_id
    assert_match(/\A\d{6}\z/, bus.pin)
  end

  test "create shows the Traccar failure and creates nothing" do
    stub_request(:post, "#{TRACCAR_API}/api/devices").to_return(status: 500, body: "boom")

    assert_no_difference -> { Bus.count } do
      post admin_buses_path, params: { bus: { license_plate: "경남70가0001" } }
    end

    assert_response :unprocessable_entity
    assert_select "li", text: /device 동기화 실패/
  end

  test "update changes the plate and syncs the device" do
    bus = buses(:two)
    put = stub_request(:put, "#{TRACCAR_API}/api/devices/#{bus.traccar_device_id}").to_return(status: 200, body: "")

    patch admin_bus_path(bus), params: { bus: { license_plate: "경남70가9999" } }

    assert_redirected_to admin_bus_path(bus)
    assert_equal "경남70가9999", bus.reload.license_plate
    assert_requested put
  end

  test "regenerate_pin issues a new pin and clears the registration" do
    bus = buses(:one)
    bus.update!(pin_registered_at: Time.current)
    old_pin = bus.pin

    post regenerate_pin_admin_bus_path(bus)

    assert_redirected_to admin_bus_path(bus)
    assert_not_equal old_pin, bus.reload.pin
    assert_nil bus.pin_registered_at
  end

  test "destroy is refused when the bus has trips and leaves the device alone" do
    assert_no_difference -> { Bus.count } do
      delete admin_bus_path(buses(:one))
    end

    assert_match(/삭제할 수 없습니다/, flash[:alert])
    assert_not_requested :delete, %r{/api/devices}
  end

  test "destroy removes a bus without trips and deletes its device" do
    bus = Bus.create!(license_plate: "경남70가0002", traccar_device_id: 777)
    stub_request(:delete, "#{TRACCAR_API}/api/devices/777").to_return(status: 204, body: "")

    assert_difference -> { Bus.count }, -1 do
      delete admin_bus_path(bus)
    end

    assert_redirected_to admin_buses_path
  end
end
