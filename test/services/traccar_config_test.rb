require "test_helper"

# config/traccar.yml 의 환경별 규칙: 로컬(development/test)은 ENV → 기본값만, 운영은 credentials → ENV(기본값 없음).
class TraccarConfigTest < ActiveSupport::TestCase
  ENV_KEYS = %w[TRACCAR_API_BASE_URL TRACCAR_API_EMAIL TRACCAR_API_PASSWORD TRACCAR_INGEST_TOKEN TRACCAR_SERVER_URL].freeze

  def config_for(env) = Rails.application.config_for(:traccar, env: env)

  # credentials 의 traccar 값을 테스트 안에서만 교체한다(운영 credentials 는 test 환경에 없다).
  def with_credentials(values = {})
    credentials = Rails.application.credentials
    credentials.define_singleton_method(:dig) { |_section, key| values[key] }
    yield
  ensure
    credentials.singleton_class.send(:remove_method, :dig)
  end

  # stub_credentials 상태가 다른 서비스 클래스에 새지 않도록 매 테스트마다 새 클래스를 쓴다.
  def client_class
    Class.new do
      include TraccarApiClient

      def self.get(path) = request(:get, path)
    end
  end

  def with_traccar_config(values)
    original = Rails.configuration.x.traccar
    Rails.configuration.x.traccar = ActiveSupport::OrderedOptions.new.merge!(values)
    yield
  ensure
    Rails.configuration.x.traccar = original
  end

  setup do
    @original_env = ENV.to_h.slice(*ENV_KEYS)
    ENV_KEYS.each { |key| ENV.delete(key) }
  end

  teardown do
    ENV_KEYS.each { |key| ENV.delete(key) }
    @original_env.each { |key, value| ENV[key] = value }
  end

  test "development는 ENV가 없으면 로컬 Traccar 기본값을 쓴다" do
    config = config_for("development")

    assert_equal "http://localhost:8082", config.api_base_url
    assert_equal "admin@localbus.test", config.api_email
    assert_equal "localbus", config.api_password
    assert_equal "http://localhost:5055", config.server_url
    assert_equal "dev-traccar-token", config.ingest_token
  end

  test "development는 ENV가 기본값보다 우선하고 credentials는 읽지 않는다" do
    ENV["TRACCAR_API_BASE_URL"] = "http://10.0.2.2:8082"

    with_credentials(api_base_url: "http://external.test", server_url: "http://external.test:5055") do
      config = config_for("development")

      assert_equal "http://10.0.2.2:8082", config.api_base_url
      assert_equal "http://localhost:5055", config.server_url
    end
  end

  test "test 환경은 ingest_token만 기본값이 있어 로컬 Traccar에 접속하지 않는다" do
    config = config_for("test")

    assert_equal "dev-traccar-token", config.ingest_token
    assert_nil config.api_base_url
    assert_nil config.server_url
  end

  test "production은 기본값이 없다" do
    with_credentials do
      config = config_for("production")

      assert_nil config.api_base_url
      assert_nil config.ingest_token
      assert_nil config.server_url
    end
  end

  test "production은 credentials를 우선하고 없으면 ENV를 쓴다" do
    ENV["TRACCAR_API_BASE_URL"] = "http://env.test"
    ENV["TRACCAR_API_EMAIL"] = "env@test.com"

    with_credentials(api_base_url: "http://cred.test") do
      config = config_for("production")

      assert_equal "http://cred.test", config.api_base_url
      assert_equal "env@test.com", config.api_email
    end
  end

  test "특수문자가 들어간 값도 그대로 읽는다" do
    with_credentials(api_password: "p#ss: w'rd \"q\"") do
      assert_equal "p#ss: w'rd \"q\"", config_for("production").api_password
    end
  end

  test "API 클라이언트는 Rails.configuration.x.traccar 의 접속 정보로 요청한다" do
    stub = stub_request(:get, "http://traccar.cfg.test/api/server")
      .with(basic_auth: [ "cfg@test.com", "cfg-secret" ])
      .to_return(status: 200, body: "{}")

    with_traccar_config(api_base_url: "http://traccar.cfg.test", api_email: "cfg@test.com", api_password: "cfg-secret") do
      client_class.get("/api/server")
    end

    assert_requested stub
  end

  test "접속 정보가 없으면 CredentialsMissing" do
    with_traccar_config({}) do
      assert_raises(TraccarApiClient::CredentialsMissing) { client_class.get("/api/server") }
    end
  end
end
