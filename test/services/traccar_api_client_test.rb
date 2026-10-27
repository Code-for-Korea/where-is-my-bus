require "test_helper"

class TraccarApiClientTest < ActiveSupport::TestCase
  setup do
    @route = Route.create!(name: "인증 시험 노선")
    @groups_url = "#{TRACCAR_API}/api/groups"
  end

  teardown { TraccarGroupSync.stub_credentials(base_url: nil, email: nil, password: nil) }

  test "uses a Bearer token when one is configured" do
    TraccarGroupSync.stub_credentials(base_url: TRACCAR_API, token: "service-token")
    stub = stub_request(:post, @groups_url)
      .with(headers: { "Authorization" => "Bearer service-token" })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: 5 }.to_json)

    assert TraccarGroupSync.call(@route).success
    assert_requested stub
  end

  test "falls back to basic auth with email and password when there is no token" do
    TraccarGroupSync.stub_credentials(base_url: TRACCAR_API, email: "admin@test.com", password: "secret")
    stub = stub_request(:post, @groups_url)
      .with(basic_auth: [ "admin@test.com", "secret" ])
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: 5 }.to_json)

    assert TraccarGroupSync.call(@route).success
    assert_requested stub
  end

  test "environment variables win over credentials" do
    TraccarGroupSync.instance_variable_set(:@stubbed, nil)
    stub = stub_request(:post, "http://env-traccar.test/api/groups")
      .with(headers: { "Authorization" => "Bearer env-token" })
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: { id: 5 }.to_json)

    with_env("TRACCAR_API_BASE_URL" => "http://env-traccar.test", "TRACCAR_API_TOKEN" => "env-token") do
      assert TraccarGroupSync.call(@route).success
    end
    assert_requested stub
  end

  private

  def with_env(vars)
    saved = vars.keys.to_h { |key| [ key, ENV[key] ] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end
end
