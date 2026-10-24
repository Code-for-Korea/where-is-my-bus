# frozen_string_literal: true

# Traccar 접속·수신 설정의 단일 출처.
#
# - 로컬(development/test): ENV만 읽는다. credentials에 외부 서버 값이 있어도 무시해서
#   로컬 작업이 실수로 외부 Traccar 서버를 건드리지 않게 한다(`bin/traccar up`이 .env에 기록).
# - 운영: credentials → ENV 순서.
module TraccarSettings
  module_function

  # key: credentials[:traccar] 아래 키, env_key: 대응하는 ENV 이름
  def fetch(key, env_key)
    from_env = ENV[env_key].presence
    return from_env if Rails.env.local?

    Rails.application.credentials.dig(:traccar, key).presence || from_env
  end
end
