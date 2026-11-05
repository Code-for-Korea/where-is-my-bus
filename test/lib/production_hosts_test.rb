require "test_helper"
require "open3"
require "json"
require "yaml"

# 운영 환경 설정(config.hosts)은 테스트 환경에서 읽히지 않으므로 운영 모드로 부팅하는 하위 프로세스에서 확인한다.
# 공개 도메인과 내부 이름이 production.rb와 deploy.yml 두 곳에 적혀 있어서, 어긋나면 이벤트 수신이 403이 된다.
class ProductionHostsTest < ActiveSupport::TestCase
  SCRIPT = <<~'RUBY'
    require "rack/mock"
    ok = ->(_env) { [ 200, {}, [ "ok" ] ] }
    config = Rails.application.config
    app = ActionDispatch::HostAuthorization.new(ok, config.hosts, **config.host_authorization)
    status = ->(host, path) { Rack::MockRequest.new(app).post(path, "HTTP_HOST" => host).status }
    puts JSON.generate(
      hosts: config.hosts,
      domain: status.call("where-is-my-bus.codefor.kr", "/integrations/traccar/events"),
      internal: status.call("rails-app:80", "/integrations/traccar/events"),
      stranger: status.call("evil.example", "/integrations/traccar/events"),
      health_check_any_host: status.call("10.0.0.5", "/up")
    )
  RUBY

  setup do
    env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1" }
    out, err, status = Open3.capture3(env, "bin/rails", "runner", SCRIPT, chdir: Rails.root.to_s)
    flunk "운영 모드 부팅 실패: #{err}" unless status.success?
    @result = JSON.parse(out.lines.last)
    @deploy = YAML.load_file(Rails.root.join("config/deploy.yml"))
  end

  test "공개 도메인과 내부 이름은 통과하고 모르는 호스트는 403이다" do
    assert_equal 200, @result["domain"]
    assert_equal 200, @result["internal"]
    assert_equal 403, @result["stranger"]
  end

  test "헬스체크 경로는 호스트와 상관없이 통과한다" do
    assert_equal 200, @result["health_check_any_host"]
  end

  test "deploy.yml의 proxy.host, network-alias, 이벤트 포워딩 주소가 허용 목록에 있다" do
    hosts = @result["hosts"]
    proxy_host = @deploy.dig("proxy", "host")
    network_alias = @deploy.dig("servers", "web", "options", "network-alias")
    forward_host = URI(@deploy.dig("accessories", "traccar", "env", "clear", "EVENT_FORWARD_URL")).host

    assert_includes hosts, proxy_host
    assert_includes hosts, network_alias
    assert_includes hosts, forward_host
  end
end
