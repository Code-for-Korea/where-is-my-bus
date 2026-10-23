ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
  end
end

module AdminAuthenticationHelper
  # Admin::BaseController는 세션 쿠키 기반 인증(Authentication concern) + operator 권한을 요구한다.
  # 실제 로그인 엔드포인트(SessionsController#create)를 통해 로그인해서 앱이 쓰는 것과
  # 동일한 방식으로 signed 쿠키가 심어지도록 한다. user의 비밀번호는 호출부에서 지정.
  def sign_in_as(user, password: "password123")
    post session_path, params: { email_address: user.email_address, password: password }
  end
end

module TraccarEventHelper
  # Traccar event.forward가 보내는 JSON과 같은 모양(docs/design-event-driven-rewrite.md 6절)의 페이로드.
  def traccar_event(type: "geofenceEnter", id: 1, at: 5.minutes.ago, unique_id: "bus-one-fixture", geofence_id: 203)
    {
      event: { id: id, type: type, eventTime: at.utc.iso8601(3), deviceId: 1, geofenceId: geofence_id, positionId: 9 },
      device: { id: 1, uniqueId: unique_id, groupId: 101 },
      geofence: { id: geofence_id }
    }
  end
end

module TraccarApiStubs
  TRACCAR_API = "http://traccar.test".freeze

  # Traccar API 호출을 쓰는 서비스에 테스트용 접속 정보를 주입한다.
  def stub_traccar_credentials(*service_classes)
    service_classes.each do |service|
      service.stub_credentials(base_url: TRACCAR_API, email: "admin@test.com", password: "secret")
    end
  end

  # TraccarDeviceGroup의 "GET device → groupId 바꿔 PUT" 흐름을 스텁한다. PUT 스텁을 돌려줘 호출 여부를 확인할 수 있다.
  def stub_device_group_move(device_id, to_group_id:)
    stub_request(:get, "#{TRACCAR_API}/api/devices/#{device_id}")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                 body: { id: device_id, name: "bus", uniqueId: "abc", groupId: 0 }.to_json)
    stub_request(:put, "#{TRACCAR_API}/api/devices/#{device_id}")
      .with(body: hash_including(groupId: to_group_id))
      .to_return(status: 200, body: "")
  end
end

class ActiveSupport::TestCase
  include TraccarEventHelper
  include TraccarApiStubs
end

class ActionDispatch::IntegrationTest
  include AdminAuthenticationHelper
end
