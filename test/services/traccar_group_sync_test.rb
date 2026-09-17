require "test_helper"

class TraccarGroupSyncTest < ActiveSupport::TestCase
  setup do
    TraccarGroupSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
    @route = routes(:one)
    @route.update!(traccar_group_id: nil)
  end

  test "creates a group when route has no traccar_group_id" do
    stub_request(:post, "http://traccar.test/api/groups")
      .with(body: { name: "route-#{@route.id}" }.to_json)
      .to_return(status: 200, body: { id: 42, name: "route-#{@route.id}" }.to_json, headers: { "Content-Type" => "application/json" })

    result = TraccarGroupSync.call(@route)

    assert result.success
    assert_equal 42, @route.reload.traccar_group_id
  end

  test "updates the group when route already has a traccar_group_id" do
    @route.update!(traccar_group_id: 42)
    stub_request(:put, "http://traccar.test/api/groups/42")
      .with(body: { id: 42, name: "route-#{@route.id}" }.to_json)
      .to_return(status: 200, body: "", headers: {})

    result = TraccarGroupSync.call(@route)

    assert result.success
    assert_equal 42, @route.reload.traccar_group_id
  end

  test "returns a failure result without raising when the API call fails" do
    stub_request(:post, "http://traccar.test/api/groups").to_return(status: 500, body: "boom")

    result = TraccarGroupSync.call(@route)

    assert result.failure?
    assert_nil @route.reload.traccar_group_id
  end

  test "destroy skips when route has no traccar_group_id" do
    result = TraccarGroupSync.destroy(@route)

    assert result.success
  end

  test "destroy deletes the group when route has a traccar_group_id" do
    @route.update!(traccar_group_id: 42)
    stub_request(:delete, "http://traccar.test/api/groups/42").to_return(status: 204, body: "")

    result = TraccarGroupSync.destroy(@route)

    assert result.success
  end

  test "destroy returns a failure result without raising when the API call fails" do
    @route.update!(traccar_group_id: 42)
    stub_request(:delete, "http://traccar.test/api/groups/42").to_return(status: 500, body: "boom")

    result = TraccarGroupSync.destroy(@route)

    assert result.failure?
  end

  test "returns a failure result without raising when credentials are not configured" do
    TraccarGroupSync.stub_credentials(base_url: nil, email: nil, password: nil)

    result = TraccarGroupSync.call(@route)

    assert result.failure?
    assert_nil @route.reload.traccar_group_id
  ensure
    TraccarGroupSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
  end
end
