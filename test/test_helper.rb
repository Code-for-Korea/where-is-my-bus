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

class ActiveSupport::TestCase
  include TraccarEventHelper
end

class ActionDispatch::IntegrationTest
  include AdminAuthenticationHelper
end
