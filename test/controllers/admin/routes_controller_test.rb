require "test_helper"

module Admin
  class RoutesControllerTest < ActionDispatch::IntegrationTest
    setup do
      TraccarGroupSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
      sign_in_as(users(:operator))
      @area = areas(:one)
    end

    test "create succeeds and calls the group creation API" do
      stub_request(:post, "http://traccar.test/api/groups")
        .to_return(status: 200, body: { id: 99, name: "route-#{Route.maximum(:id).to_i + 1}" }.to_json, headers: { "Content-Type" => "application/json" })

      assert_difference "Route.count", 1 do
        post admin_routes_path, params: { route: { area_id: @area.id, name: "새 노선" } }
      end

      route = Route.order(:id).last
      assert_redirected_to admin_route_path(route)
      assert_equal 99, route.reload.traccar_group_id
      assert_nil flash[:alert]
    end

    test "create rolls back and does not save the route when the group API fails" do
      stub_request(:post, "http://traccar.test/api/groups").to_return(status: 500, body: "boom")

      assert_no_difference "Route.count" do
        post admin_routes_path, params: { route: { area_id: @area.id, name: "새 노선" } }
      end

      assert_response :unprocessable_entity
      assert_match(/Traccar 연동 실패/, response.body)
    end

    test "destroy calls the group deletion API" do
      route = routes(:one)
      route.update!(traccar_group_id: 42)
      stub_request(:delete, "http://traccar.test/api/groups/42").to_return(status: 204, body: "")

      assert_difference "Route.count", -1 do
        delete admin_route_path(route)
      end

      assert_redirected_to admin_routes_path
      assert_requested :delete, "http://traccar.test/api/groups/42"
    end

    test "destroy keeps the route when the group deletion API fails" do
      route = routes(:one)
      route.update!(traccar_group_id: 42)
      stub_request(:delete, "http://traccar.test/api/groups/42").to_return(status: 500, body: "boom")

      assert_no_difference "Route.count" do
        delete admin_route_path(route)
      end

      assert_redirected_to admin_route_path(route)
      assert_match(/삭제할 수 없습니다/, flash[:alert])
    end

    test "sync_group succeeds and shows a notice" do
      route = routes(:one)
      route.update!(traccar_group_id: 42)
      stub_request(:put, "http://traccar.test/api/groups/42").to_return(status: 200, body: "")

      post sync_group_admin_route_path(route)

      assert_redirected_to admin_route_path(route)
      assert_match(/성공/, flash[:notice])
    end

    test "sync_group failure shows a flash alert" do
      route = routes(:one)
      route.update!(traccar_group_id: 42)
      stub_request(:put, "http://traccar.test/api/groups/42").to_return(status: 500, body: "boom")

      post sync_group_admin_route_path(route)

      assert_redirected_to admin_route_path(route)
      assert_match(/group 동기화 실패/, flash[:alert])
    end
  end
end
