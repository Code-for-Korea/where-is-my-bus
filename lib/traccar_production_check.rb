# 운영 부팅 때 Traccar 설정이 비어 있거나 개발용이 아닌지 검사한다 (config/initializers/traccar_production_check.rb).
# 값을 빠뜨리면 앱은 /up 200으로 정상처럼 뜨는데 이벤트 수신이 전부 401이 되고 운전자 앱 등록이 깨지며, 공개된 개발 토큰(dev-traccar-*)이
# 운영에 쓰일 수 있다. 부팅을 막아 배포 때 드러내려는 검사다. 값의 모양만 보며(연결 여부는 보지 않는다) 한계와 이유는 docs/deployment.md "부팅 검사".
class TraccarProductionCheck
  DEV_HOSTS = /iptime\.org|localhost|127\.0\.0\.1/i

  # 설정 이름 => [환경변수, credentials 키]. 조회 순서는 코드가 쓰는 것과 같다(환경변수 우선).
  SETTINGS = {
    api_base_url: [ "TRACCAR_API_BASE_URL", :api_base_url ],
    api_token: [ "TRACCAR_API_TOKEN", :api_token ],
    ingest_token: [ "TRACCAR_INGEST_TOKEN", :ingest_token ],
    server_url: [ "TRACCAR_SERVER_URL", :server_url ]
  }.freeze

  def self.problems(env: ENV, credentials: Rails.application.credentials)
    values = SETTINGS.transform_values do |(env_key, credentials_key)|
      env[env_key].presence || credentials.dig(:traccar, credentials_key).presence
    end

    problems = values.select { |_, value| value.blank? }.keys.map { |name| "#{name} 없음" }
    %i[api_token ingest_token].each do |name|
      problems << "#{name}가 개발용 값(dev-...)" if values[name].to_s.start_with?("dev-")
    end
    %i[api_base_url server_url].each do |name|
      problems << "#{name}가 개발 서버를 가리킴(#{values[name]})" if values[name].to_s.match?(DEV_HOSTS)
    end
    problems
  end
end
