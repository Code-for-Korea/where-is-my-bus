require "test_helper"

class TraccarProductionCheckTest < ActiveSupport::TestCase
  PRODUCTION = {
    traccar: {
      api_base_url: "https://testtraccar.codefor.kr",
      api_token: "prod-api-token-0123456789",
      ingest_token: "prod-ingest-token-0123456789",
      server_url: "https://testtraccar.codefor.kr:5055"
    }
  }.freeze

  test "운영 값이 모두 있으면 문제가 없다" do
    assert_empty TraccarProductionCheck.problems(env: {}, credentials: PRODUCTION)
  end

  test "비어 있는 설정을 모두 알려 준다" do
    problems = TraccarProductionCheck.problems(env: {}, credentials: {})

    assert_equal %w[api_base_url api_token ingest_token server_url].map { |name| "#{name} 없음" }, problems
  end

  test "환경변수가 credentials보다 우선한다" do
    credentials = { traccar: PRODUCTION[:traccar].merge(api_base_url: "http://dev-box.iptime.org:8082") }

    assert_empty TraccarProductionCheck.problems(env: { "TRACCAR_API_BASE_URL" => "https://testtraccar.codefor.kr" }, credentials: credentials)
  end

  test "예전 개발 서버를 가리키면 거부한다" do
    credentials = { traccar: PRODUCTION[:traccar].merge(api_base_url: "http://dev-box.iptime.org:8082") }

    assert_match(/api_base_url가 개발 서버를 가리킴/, TraccarProductionCheck.problems(env: {}, credentials: credentials).join)
  end

  test "공개된 개발 토큰은 거부한다" do
    env = { "TRACCAR_API_TOKEN" => "dev-traccar-api-token", "TRACCAR_INGEST_TOKEN" => "dev-traccar-token" }

    assert_equal [ "api_token가 개발용 값(dev-...)", "ingest_token가 개발용 값(dev-...)" ],
                 TraccarProductionCheck.problems(env: env, credentials: PRODUCTION)
  end
end
