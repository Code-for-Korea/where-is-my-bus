require "test_helper"
require "open3"
require "yaml"

# 운영 부팅 때 Traccar 설정을 검사하는 TraccarProductionCheck(lib/traccar_production_check.rb)와 이니셜라이저
# (config/initializers/traccar_production_check.rb)를 확인한다. 세 부분이다.
#
#   1. 값의 출처(환경변수, credentials)와 거부 규칙
#   2. 배포 설정(deploy.yml, .kamal/secrets)이 이 검사를 통과하는 값을 실제로 내려 주는지
#   3. 운영 모드로 부팅하는 하위 프로세스에서 이니셜라이저가 부팅을 막거나 통과시키는지 (아래 두 번째 클래스)
class TraccarProductionCheckTest < ActiveSupport::TestCase
  # 운영에서 쓰는 모양이다. Traccar는 같은 서버의 accessory라 Rails가 도커 네트워크 안 이름으로 부르고,
  # 위치 수신 주소는 첫 배포에서 임시로 평문 5055다(HTTPS 전환은 docs/future-improvements.md 32번).
  VALID_ENV = {
    "TRACCAR_API_BASE_URL" => "http://where-is-my-bus-traccar:8082",
    "TRACCAR_API_TOKEN" => "prod-api-token-0123456789",
    "TRACCAR_INGEST_TOKEN" => "prod-ingest-token-0123456789",
    "TRACCAR_SERVER_URL" => "http://where-is-my-bus.codefor.kr:5055"
  }.freeze

  VALID_CREDENTIALS = {
    traccar: {
      api_base_url: VALID_ENV["TRACCAR_API_BASE_URL"],
      api_token: VALID_ENV["TRACCAR_API_TOKEN"],
      ingest_token: VALID_ENV["TRACCAR_INGEST_TOKEN"],
      server_url: VALID_ENV["TRACCAR_SERVER_URL"]
    }
  }.freeze

  DEV_URLS = %w[http://dev-box.iptime.org:8082 http://localhost:8082 http://127.0.0.1:5055 http://LOCALHOST:5055].freeze

  # 기본 인자는 실제 ENV와 Rails.application.credentials라서 이 PC의 환경에 따라 결과가 달라진다. 항상 명시해서 부른다.
  def problems(env: {}, credentials: {})
    TraccarProductionCheck.problems(env: env, credentials: credentials)
  end

  # --- 1. 값의 출처와 거부 규칙 -------------------------------------------------------------------

  test "환경변수 네 개가 모두 있으면 문제가 없다" do
    assert_empty problems(env: VALID_ENV)
  end

  test "credentials에만 있어도 문제가 없다" do
    assert_empty problems(credentials: VALID_CREDENTIALS)
  end

  test "아무것도 없으면 네 가지를 모두 순서대로 알려 준다" do
    assert_equal [ "api_base_url 없음", "api_token 없음", "ingest_token 없음", "server_url 없음" ], problems
  end

  test "일부만 없으면 빠진 것만 알려 준다" do
    assert_equal [ "ingest_token 없음" ], problems(env: VALID_ENV.except("TRACCAR_INGEST_TOKEN"))
  end

  test "환경변수가 credentials보다 우선한다" do
    credentials = { traccar: VALID_CREDENTIALS[:traccar].merge(api_base_url: DEV_URLS.first) }

    assert_empty problems(env: { "TRACCAR_API_BASE_URL" => VALID_ENV["TRACCAR_API_BASE_URL"] }, credentials: credentials)
  end

  test "환경변수의 개발용 값은 credentials가 올바라도 거부한다" do
    env = { "TRACCAR_API_TOKEN" => "dev-traccar-api-token" }

    assert_equal [ "api_token가 개발용 값(dev-...)" ], problems(env: env, credentials: VALID_CREDENTIALS)
  end

  test "빈 문자열과 공백만 있는 환경변수는 없는 것으로 보고 credentials로 넘어간다" do
    blank_env = VALID_ENV.transform_values { |value| value.empty? ? value : "  " }.merge("TRACCAR_API_TOKEN" => "")

    assert_empty problems(env: blank_env, credentials: VALID_CREDENTIALS)
    assert_equal 4, problems(env: blank_env).size
  end

  test "공개된 개발 토큰은 거부한다" do
    { "TRACCAR_API_TOKEN" => "api_token", "TRACCAR_INGEST_TOKEN" => "ingest_token" }.each do |env_key, name|
      assert_equal [ "#{name}가 개발용 값(dev-...)" ], problems(env: VALID_ENV.merge(env_key => "dev-traccar-token")), env_key
    end
  end

  test "dev-로 시작하지 않는 토큰은 이름에 dev가 들어 있어도 거부하지 않는다" do
    assert_empty problems(env: VALID_ENV.merge("TRACCAR_API_TOKEN" => "prod-dev-token", "TRACCAR_INGEST_TOKEN" => "devtoken"))
  end

  test "개발 서버를 가리키는 주소는 거부한다" do
    { "TRACCAR_API_BASE_URL" => "api_base_url", "TRACCAR_SERVER_URL" => "server_url" }.each do |env_key, name|
      DEV_URLS.each do |url|
        assert_equal [ "#{name}가 개발 서버를 가리킴(#{url})" ], problems(env: VALID_ENV.merge(env_key => url)), "#{env_key}=#{url}"
      end
    end
  end

  test "운영 주소는 거부하지 않는다" do
    api_base_urls = %w[http://where-is-my-bus-traccar:8082 https://traccar.example.org]
    # 첫 배포의 평문 5055와 HTTPS 전환 뒤 서브도메인. HTTPS를 필수로 바꾸면 평문 항목을 이 목록에서 뺀다.
    server_urls = %w[http://where-is-my-bus.codefor.kr:5055 https://traccar-where-is-my-bus.codefor.kr]

    api_base_urls.each { |url| assert_empty problems(env: VALID_ENV.merge("TRACCAR_API_BASE_URL" => url)), url }
    server_urls.each { |url| assert_empty problems(env: VALID_ENV.merge("TRACCAR_SERVER_URL" => url)), url }
  end

  test "여러 문제는 없음, 개발용 토큰, 개발 서버 순서로 한꺼번에 알려 준다" do
    env = VALID_ENV.except("TRACCAR_INGEST_TOKEN").merge(
      "TRACCAR_API_TOKEN" => "dev-traccar-api-token",
      "TRACCAR_API_BASE_URL" => "http://localhost:8082",
      "TRACCAR_SERVER_URL" => "http://127.0.0.1:5055"
    )

    assert_equal [ "ingest_token 없음",
                   "api_token가 개발용 값(dev-...)",
                   "api_base_url가 개발 서버를 가리킴(http://localhost:8082)",
                   "server_url가 개발 서버를 가리킴(http://127.0.0.1:5055)" ], problems(env: env)
  end

  # --- 2. 배포 설정과의 일치 ----------------------------------------------------------------------

  # 운영에는 credentials에 traccar 값이 없고(production.yml.enc에 넣지 않는다) deploy.yml이 환경변수로 내려 준다.
  # 하나라도 빠지면 컨테이너가 부팅하지 못하므로 올리기 전에 여기서 잡는다.
  test "deploy.yml이 운영 Traccar 설정 네 가지를 모두 환경변수로 내려 준다" do
    provided = provided_env_names

    TraccarProductionCheck::SETTINGS.each do |name, (env_key, _)|
      assert_includes provided, env_key, "#{name}(#{env_key})을 deploy.yml이 내려 주지 않는다"
    end
  end

  test "deploy.yml이 내려 주는 값은 운영 검사를 통과한다" do
    clear = deploy.dig("env", "clear")
    env = TraccarProductionCheck::SETTINGS.values.to_h { |(env_key, _)| [ env_key, clear[env_key] || "prod-secret-placeholder-0123" ] }

    assert_empty problems(env: env.transform_values(&:to_s))
  end

  test "deploy.yml의 비밀 이름은 모두 .kamal/secrets에 정의돼 있다" do
    defined = File.readlines(Rails.root.join(".kamal/secrets")).filter_map { |line| line[/\A([A-Z][A-Z0-9_]*)=/, 1] }

    assert_empty secret_names - defined, "deploy.yml이 쓰지만 .kamal/secrets에 없는 비밀"
  end

  test "SETTINGS의 환경변수 이름은 앱 코드가 읽는 이름과 같다" do
    sources = %w[
      app/services/concerns/traccar_api_client.rb
      app/controllers/integrations/traccar_events_controller.rb
      app/controllers/integrations/traccar_controller.rb
    ].map { |path| File.read(Rails.root.join(path)) }.join("\n")

    TraccarProductionCheck::SETTINGS.each_value do |(env_key, _)|
      assert_includes sources, %(ENV["#{env_key}"]), "#{env_key}를 읽는 앱 코드가 없다. 이름이 바뀌었으면 SETTINGS도 바꾼다"
    end
  end

  private

  def deploy
    @deploy ||= YAML.load_file(Rails.root.join("config/deploy.yml"))
  end

  def provided_env_names
    deploy.dig("env", "clear").keys + deploy.dig("env", "secret")
  end

  # env.secret, accessory의 env.secret, registry 자격 증명에서 쓰는 비밀 이름
  def secret_names
    accessory_secrets = deploy.fetch("accessories", {}).values.flat_map { |accessory| accessory.dig("env", "secret") || [] }
    registry = deploy.fetch("registry", {}).slice("username", "password").values.flatten

    (deploy.dig("env", "secret") + accessory_secrets + registry).uniq
  end
end

# 이니셜라이저가 운영 모드 부팅을 실제로 막는지. 운영 설정은 테스트 환경에서 읽히지 않으므로 하위 프로세스로 부팅한다.
# 이 PC의 환경(예전 credentials.yml.enc, 이미 export한 TRACCAR_* 환경변수)에 결과가 달라지지 않도록 필요한 값을 모두 명시하고
# 나머지는 지운다. api_base_url은 항상 환경변수로 줘서 옛 credentials에 있을 수 있는 개발 서버 주소를 가린다.
class TraccarProductionCheckBootTest < ActiveSupport::TestCase
  VALID = TraccarProductionCheckTest::VALID_ENV
  CLEARED = (TraccarProductionCheck::SETTINGS.values.map(&:first) + %w[SECRET_KEY_BASE_DUMMY]).index_with(nil).freeze

  def boot(env)
    environment = CLEARED.merge("RAILS_ENV" => "production", "SECRET_KEY_BASE" => "x" * 64).merge(env)
    Open3.capture3(environment, "bin/rails", "runner", "puts :booted", chdir: Rails.root.to_s)
  end

  test "필수 설정이 빠지면 운영 부팅이 실패하고 빠진 것을 알려 준다" do
    out, err, status = boot("TRACCAR_API_BASE_URL" => VALID["TRACCAR_API_BASE_URL"])

    assert_not status.success?
    assert_not_includes out, "booted"
    assert_equal "api_token 없음, ingest_token 없음, server_url 없음", err[/운영 Traccar 설정 오류: (.+?) \(RuntimeError\)/, 1]
  end

  test "값이 모두 맞으면 운영 모드로 부팅한다" do
    out, err, status = boot(VALID)

    assert status.success?, err
    assert_includes out, "booted"
  end

  test "SECRET_KEY_BASE_DUMMY가 있으면(이미지 빌드) 운영 값이 없어도 검사를 건너뛴다" do
    out, err, status = boot("SECRET_KEY_BASE_DUMMY" => "1", "SECRET_KEY_BASE" => nil)

    assert status.success?, err
    assert_includes out, "booted"
  end
end
