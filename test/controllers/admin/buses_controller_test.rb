require "test_helper"

class Admin::BusesControllerTest < ActionDispatch::IntegrationTest
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    stub_traccar_credentials(TraccarDeviceSync, TraccarDeviceGroup)
    sign_in_as(users(:operator))
  end

  test "index shows each bus's assigned route and whether it is running" do
    get admin_buses_path

    assert_response :ok
    assert_select "td a", text: "1번 노선"
    assert_select "td", text: "운행 중"
    assert_select "td", text: "운행 안 함"
  end

  test "index flags a bus without a route" do
    buses(:two).update_columns(route_id: nil)

    get admin_buses_path

    assert_select "td span", text: "미배정"
  end

  test "show displays the pin, registration state, assigned route and running trip" do
    get admin_bus_path(buses(:one))

    assert_response :ok
    assert_select ".font-mono", text: buses(:one).pin
    assert_select "a", text: "1번 노선", minimum: 1
    assert_select "span", text: /미등록/
  end

  test "show warns that an unassigned bus cannot start" do
    buses(:two).update_columns(route_id: nil)

    get admin_bus_path(buses(:two))

    assert_select ".text-amber-600", text: /배정된 노선이 없습니다/
  end

  test "the form offers every route to assign" do
    get new_admin_bus_path

    assert_select "select[name='bus[route_id]'] option", count: 1 + Route.count
    assert_select "select[name='bus[route_id]'] option", text: "배정 안 함"
  end

  test "create registers the bus and its Traccar device with a generated pin" do
    stub_request(:post, "#{TRACCAR_API}/api/devices")
      .to_return(status: 200, headers: JSON_HEADERS, body: { id: 66 }.to_json)

    assert_difference -> { Bus.count }, 1 do
      post admin_buses_path, params: { bus: { license_plate: "경남70가0001", bus_number: "3번" } }
    end

    bus = Bus.find_by!(license_plate: "경남70가0001")
    assert_redirected_to admin_bus_path(bus)
    assert_equal 66, bus.traccar_device_id
    assert_nil bus.route
    assert_match(/\A\d{6}\z/, bus.pin)
    assert_not_requested :get, %r{/api/devices/66} # 노선이 없으면 group을 건드리지 않는다
  end

  test "create with a route also puts the new device into that route's Traccar group" do
    stub_request(:post, "#{TRACCAR_API}/api/devices")
      .to_return(status: 200, headers: JSON_HEADERS, body: { id: 66 }.to_json)
    move = stub_device_group_move(66, to_group_id: routes(:two).traccar_group_id)

    post admin_buses_path, params: { bus: { license_plate: "경남70가0001", route_id: routes(:two).id } }

    assert_equal routes(:two), Bus.find_by!(license_plate: "경남70가0001").route
    assert_requested move
  end

  test "create shows the Traccar failure and creates nothing" do
    stub_request(:post, "#{TRACCAR_API}/api/devices").to_return(status: 500, body: "boom")

    assert_no_difference -> { Bus.count } do
      post admin_buses_path, params: { bus: { license_plate: "경남70가0001" } }
    end

    assert_response :unprocessable_entity
    assert_select "li", text: /Traccar 차량 동기화 실패/
  end

  test "update changes the plate and syncs the device and its group" do
    bus = buses(:two)
    stub_device_update(bus.traccar_device_id)
    move = stub_device_group_move(bus.traccar_device_id, to_group_id: routes(:two).traccar_group_id)

    patch admin_bus_path(bus), params: { bus: { license_plate: "경남70가9999" } }

    assert_redirected_to admin_bus_path(bus)
    assert_equal "경남70가9999", bus.reload.license_plate
    assert_requested move
  end

  test "changing the route moves the device to the new route's group" do
    bus = buses(:two)
    stub_device_update(bus.traccar_device_id)
    move = stub_device_group_move(bus.traccar_device_id, to_group_id: routes(:one).traccar_group_id)

    patch admin_bus_path(bus), params: { bus: { route_id: routes(:one).id } }

    assert_equal routes(:one), bus.reload.route
    assert_requested move
  end

  test "removing the route takes the device out of its group" do
    bus = buses(:two)
    stub_device_update(bus.traccar_device_id)
    clear = stub_device_group_move(bus.traccar_device_id, to_group_id: 0)

    patch admin_bus_path(bus), params: { bus: { route_id: "" } }

    assert_nil bus.reload.route
    assert_requested clear
  end

  test "the route cannot be changed while the bus is running" do
    bus = buses(:one)

    patch admin_bus_path(bus), params: { bus: { route_id: routes(:two).id } }

    assert_response :unprocessable_entity
    assert_select "li", text: /운행 중에는 바꿀 수 없습니다/
    assert_equal routes(:one), bus.reload.route
    assert_not_requested :any, %r{traccar.test}
  end

  test "a Traccar failure while moving the group keeps the old route" do
    bus = buses(:two)
    stub_device_update(bus.traccar_device_id)
    stub_request(:get, "#{TRACCAR_API}/api/devices/#{bus.traccar_device_id}").to_return(status: 500, body: "boom")

    patch admin_bus_path(bus), params: { bus: { route_id: routes(:one).id } }

    assert_response :unprocessable_entity
    assert_equal routes(:two), bus.reload.route
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
