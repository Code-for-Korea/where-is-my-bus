require "test_helper"

class TraccarSettingsTest < ActiveSupport::TestCase
  ENV_KEYS = %w[TRACCAR_API_BASE_URL TRACCAR_API_EMAIL TRACCAR_API_PASSWORD TRACCAR_INGEST_TOKEN].freeze

  # stub_credentials 상태가 다른 서비스 클래스에 새지 않도록 매 테스트마다 새 클래스를 쓴다.
  def client_class
    Class.new do
      include TraccarApiClient

      def self.get(path) = request(:get, path)
    end
  end

  # credentials의 traccar 값을 테스트 안에서만 교체한다(개발자 로컬 credentials에 실제 값이 있을 수 있다).
  def with_credentials(values = {})
    credentials = Rails.application.credentials
    credentials.define_singleton_method(:dig) { |_section, key| values[key] }
    yield
  ensure
    credentials.singleton_class.send(:remove_method, :dig)
  end

  def as_production
    env = Rails.env
    env.define_singleton_method(:local?) { false }
    yield
  ensure
    env.singleton_class.send(:remove_method, :local?)
  end

  setup do
    @original_env = ENV.to_h.slice(*ENV_KEYS)
    ENV_KEYS.each { |key| ENV.delete(key) }
  end

  teardown do
    ENV_KEYS.each { |key| ENV.delete(key) }
    @original_env.each { |key, value| ENV[key] = value }
  end

  test "로컬은 ENV만 읽고 credentials는 무시한다" do
    ENV["TRACCAR_API_BASE_URL"] = "http://localhost:8082"

    with_credentials(api_base_url: "http://external.test") do
      assert_equal "http://localhost:8082", TraccarSettings.fetch(:api_base_url, "TRACCAR_API_BASE_URL")
    end
  end

  test "로컬에서 ENV가 없으면 credentials에 값이 있어도 nil" do
    with_credentials(api_base_url: "http://external.test") do
      assert_nil TraccarSettings.fetch(:api_base_url, "TRACCAR_API_BASE_URL")
    end
  end

  test "운영은 credentials를 우선하고 없으면 ENV" do
    ENV["TRACCAR_API_BASE_URL"] = "http://env.test"

    as_production do
      with_credentials(api_base_url: "http://cred.test") do
        assert_equal "http://cred.test", TraccarSettings.fetch(:api_base_url, "TRACCAR_API_BASE_URL")
      end
      with_credentials do
        assert_equal "http://env.test", TraccarSettings.fetch(:api_base_url, "TRACCAR_API_BASE_URL")
      end
    end
  end

  test "API 클라이언트는 로컬에서 ENV의 접속 정보로 요청한다" do
    ENV["TRACCAR_API_BASE_URL"] = "http://traccar.env.test"
    ENV["TRACCAR_API_EMAIL"] = "env@test.com"
    ENV["TRACCAR_API_PASSWORD"] = "env-secret"
    stub = stub_request(:get, "http://traccar.env.test/api/server")
      .with(basic_auth: [ "env@test.com", "env-secret" ])
      .to_return(status: 200, body: "{}")

    with_credentials(api_base_url: "http://external.test", api_email: "x", api_password: "y") do
      client_class.get("/api/server")
    end

    assert_requested stub
  end

  test "API 클라이언트는 운영에서 credentials의 접속 정보로 요청한다" do
    ENV["TRACCAR_API_BASE_URL"] = "http://traccar.env.test"
    stub = stub_request(:get, "http://traccar.cred.test/api/server")
      .with(basic_auth: [ "cred@test.com", "cred-secret" ])
      .to_return(status: 200, body: "{}")

    as_production do
      with_credentials(api_base_url: "http://traccar.cred.test", api_email: "cred@test.com", api_password: "cred-secret") do
        client_class.get("/api/server")
      end
    end

    assert_requested stub
  end

  test "접속 정보가 없으면 CredentialsMissing" do
    assert_raises(TraccarApiClient::CredentialsMissing) { client_class.get("/api/server") }
  end
end
