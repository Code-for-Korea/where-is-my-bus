require "test_helper"

class RouteRegistrationTest < ActiveSupport::TestCase
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    TraccarGroupSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
  end

  test "create saves the route and creates its Traccar group" do
    stub_request(:post, "http://traccar.test/api/groups")
      .with(body: { name: "3번 노선" }.to_json)
      .to_return(status: 200, body: { id: 77 }.to_json, headers: JSON_HEADERS)

    result = RouteRegistration.create(name: "3번 노선")

    assert result.success?
    assert_equal 77, result.record.reload.traccar_group_id
  end

  test "create returns validation errors without calling Traccar" do
    result = RouteRegistration.create(name: routes(:one).name)

    assert result.failure?
    assert_predicate result.error, :present?
    assert result.record.new_record?
    assert_not_requested :post, "http://traccar.test/api/groups"
  end

  test "create rolls back the route when Traccar fails" do
    stub_request(:post, "http://traccar.test/api/groups").to_return(status: 500, body: "boom")

    assert_no_difference -> { Route.count } do
      result = RouteRegistration.create(name: "3번 노선")

      assert result.failure?
      assert_match(/Traccar 노선 동기화 실패/, result.error)
      assert result.record.new_record?
    end
  end

  test "update renames the route and the Traccar group" do
    route = routes(:one)
    put = stub_request(:put, "http://traccar.test/api/groups/#{route.traccar_group_id}")
      .with(body: { id: route.traccar_group_id, name: "새 이름" }.to_json)
      .to_return(status: 200, body: "")

    result = RouteRegistration.update(route, name: "새 이름")

    assert result.success?
    assert_equal "새 이름", route.reload.name
    assert_requested put
  end

  test "update rolls back the new name when Traccar fails" do
    route = routes(:one)
    original = route.name
    stub_request(:put, "http://traccar.test/api/groups/#{route.traccar_group_id}").to_return(status: 500, body: "boom")

    result = RouteRegistration.update(route, name: "새 이름")

    assert result.failure?
    assert_equal original, route.reload.name
  end

  test "destroy removes the route and deletes its Traccar group" do
    route = Route.create!(name: "임시 노선", traccar_group_id: 900)
    delete = stub_request(:delete, "http://traccar.test/api/groups/900").to_return(status: 204, body: "")

    result = RouteRegistration.destroy(route)

    assert result.success?
    assert_not Route.exists?(route.id)
    assert_requested delete
  end

  test "destroy leaves Traccar untouched when the route has trips" do
    result = RouteRegistration.destroy(routes(:one))

    assert result.failure?
    assert Route.exists?(routes(:one).id)
    assert_not_requested :delete, %r{traccar.test/api/groups}
  end

  test "destroy keeps the route when Traccar deletion fails" do
    route = Route.create!(name: "임시 노선", traccar_group_id: 900)
    stub_request(:delete, "http://traccar.test/api/groups/900").to_return(status: 500, body: "boom")

    result = RouteRegistration.destroy(route)

    assert result.failure?
    assert Route.exists?(route.id)
  end
end
