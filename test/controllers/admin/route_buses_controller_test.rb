require "test_helper"

module Admin
  class RouteBusesControllerTest < ActionDispatch::IntegrationTest
    setup do
      TraccarGroupMembership.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
      sign_in_as(users(:operator))
      @route = routes(:one)
      @route.update!(traccar_group_id: 42)
      @bus = buses(:one)
      @bus.update!(traccar_device_id: 5)
    end

    test "create adds the route_bus and calls the membership add API" do
      stub_request(:get, "http://traccar.test/api/devices/5")
        .to_return(status: 200, body: { id: 5, groupId: 0 }.to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:put, "http://traccar.test/api/devices/5").to_return(status: 200, body: "")

      assert_difference "RouteBus.count", 1 do
        post admin_route_route_buses_path(@route), params: { bus_id: @bus.id }
      end

      assert_redirected_to admin_route_path(@route)
      assert_requested :put, "http://traccar.test/api/devices/5" do |req|
        JSON.parse(req.body)["groupId"] == 42
      end
      assert_nil flash[:alert]
    end

    test "create still creates the route_bus and sets a flash alert when the membership API fails" do
      stub_request(:get, "http://traccar.test/api/devices/5").to_return(status: 500, body: "boom")

      assert_difference "RouteBus.count", 1 do
        post admin_route_route_buses_path(@route), params: { bus_id: @bus.id }
      end

      assert_redirected_to admin_route_path(@route)
      assert_match(/group 연결 실패/, flash[:alert])
    end

    test "destroy removes the route_bus and calls the membership remove API" do
      route_bus = RouteBus.create!(route: @route, bus: @bus)
      stub_request(:get, "http://traccar.test/api/devices/5")
        .to_return(status: 200, body: { id: 5, groupId: 42 }.to_json, headers: { "Content-Type" => "application/json" })
      stub_request(:put, "http://traccar.test/api/devices/5").to_return(status: 200, body: "")

      assert_difference "RouteBus.count", -1 do
        delete admin_route_route_bus_path(@route, route_bus)
      end

      assert_redirected_to admin_route_path(@route)
      assert_requested :put, "http://traccar.test/api/devices/5" do |req|
        JSON.parse(req.body)["groupId"] == 0
      end
    end

    test "destroy still removes the route_bus when the membership API fails" do
      route_bus = RouteBus.create!(route: @route, bus: @bus)
      stub_request(:get, "http://traccar.test/api/devices/5").to_return(status: 500, body: "boom")

      assert_difference "RouteBus.count", -1 do
        delete admin_route_route_bus_path(@route, route_bus)
      end

      assert_redirected_to admin_route_path(@route)
    end
  end
end
