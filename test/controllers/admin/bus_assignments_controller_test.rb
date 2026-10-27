require "test_helper"

# 픽스처: 버스 one은 1번 노선(운행 중), 버스 two는 2번 노선(운행 중 아님).
class Admin::BusAssignmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    stub_traccar_credentials(TraccarDeviceSync, TraccarDeviceGroup)
    sign_in_as(users(:operator))
  end

  test "the route page lists assigned buses and the buses that could be assigned" do
    get admin_route_path(routes(:one))

    assert_response :ok
    assert_select "h2", text: "배정 차량"
    assert_select "li a", text: buses(:one).license_plate
    assert_select "li span", text: /운행 중/
    assert_select "select[name=bus_id] option", text: buses(:two).assignment_label
    assert_select "select[name=bus_id] option", text: /#{buses(:one).license_plate}/, count: 0
  end

  test "assigning a bus puts its device into the route's Traccar group" do
    bus = buses(:two)
    stub_device_update(bus.traccar_device_id)
    move = stub_device_group_move(bus.traccar_device_id, to_group_id: routes(:one).traccar_group_id)

    post admin_route_bus_assignments_path(routes(:one)), params: { bus_id: bus.id }

    assert_redirected_to admin_route_path(routes(:one))
    assert_equal routes(:one), bus.reload.route
    assert_requested move
  end

  test "assigning a bus that is on another route moves it" do
    assert_equal routes(:two), buses(:two).route
    stub_device_update(buses(:two).traccar_device_id)
    stub_device_group_move(buses(:two).traccar_device_id, to_group_id: routes(:one).traccar_group_id)

    post admin_route_bus_assignments_path(routes(:one)), params: { bus_id: buses(:two).id }

    assert_equal [ buses(:one), buses(:two) ].sort_by(&:id), routes(:one).buses.sort_by(&:id)
    assert_empty routes(:two).buses
  end

  test "a bus that is running cannot be moved to another route" do
    post admin_route_bus_assignments_path(routes(:two)), params: { bus_id: buses(:one).id }

    assert_redirected_to admin_route_path(routes(:two))
    assert_match(/운행 중에는 바꿀 수 없습니다/, flash[:alert])
    assert_equal routes(:one), buses(:one).reload.route
  end

  test "a Traccar failure leaves the bus where it was" do
    bus = buses(:two)
    stub_device_update(bus.traccar_device_id)
    stub_request(:get, "#{TRACCAR_API}/api/devices/#{bus.traccar_device_id}").to_return(status: 500, body: "boom")

    post admin_route_bus_assignments_path(routes(:one)), params: { bus_id: bus.id }

    assert_match(/배정할 수 없습니다/, flash[:alert])
    assert_equal routes(:two), bus.reload.route
  end

  test "assigning without choosing a bus asks to choose one" do
    post admin_route_bus_assignments_path(routes(:one)), params: { bus_id: "" }

    assert_match(/차량을 선택해 주세요/, flash[:alert])
  end

  test "unassigning takes the device out of the group" do
    bus = buses(:two)
    stub_device_update(bus.traccar_device_id)
    clear = stub_device_group_move(bus.traccar_device_id, to_group_id: 0)

    delete admin_route_bus_assignment_path(routes(:two), bus)

    assert_redirected_to admin_route_path(routes(:two))
    assert_nil bus.reload.route
    assert_requested clear
  end

  test "a running bus cannot be unassigned" do
    delete admin_route_bus_assignment_path(routes(:one), buses(:one))

    assert_match(/배정을 풀 수 없습니다/, flash[:alert])
    assert_equal routes(:one), buses(:one).reload.route
  end

  test "a route with assigned buses cannot be deleted" do
    route = Route.create!(name: "임시")
    Bus.create!(license_plate: "경남70가0003", route: route)

    assert_no_difference -> { Route.count } do
      delete admin_route_path(route)
    end

    assert_match(/배정된 차량/, flash[:alert])
  end
end
