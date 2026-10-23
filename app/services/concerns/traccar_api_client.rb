# frozen_string_literal: true

require "net/http"
require "json"

# Traccar 서비스 객체(TraccarGroupSync/TraccarGeofenceSync/TraccarRouteStopLink/TraccarDeviceGroup/TraccarDeviceSync) 공통 HTTP 클라이언트.
# Result 패턴, credentials 조회, Net::HTTP 기반 request 헬퍼, 테스트용 stub_credentials를 제공한다.
module TraccarApiClient
  extend ActiveSupport::Concern

  Result = Struct.new(:success, :error, keyword_init: true) do
    def failure? = !success
  end

  RESCUED_ERRORS = [
    Timeout::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError,
    Errno::ECONNREFUSED, Errno::ECONNRESET, JSON::ParserError, RuntimeError,
    ActiveRecord::RecordInvalid
  ].freeze

  class CredentialsMissing < RuntimeError; end

  included do
    # 각 서비스 클래스에서 Result를 그대로 참조할 수 있도록 상수를 노출 (예: TraccarGroupSync::Result)
    const_set(:Result, TraccarApiClient::Result) unless const_defined?(:Result, false)
  end

  class_methods do
    # 테스트용: credentials 대신 명시적으로 접속 정보를 주입
    def stub_credentials(base_url:, email: nil, password: nil, token: nil)
      @stubbed = { base_url: base_url, email: email, password: password, token: token }
    end

    private

    # 접속 정보: 환경변수가 credentials보다 우선한다 (로컬 Docker 구성이 credentials의 원격 서버 설정을 덮어쓸 수 있게).
    # token(Traccar의 web.serviceAccountToken)이 있으면 Bearer 인증, 없으면 email/password 기본 인증.
    def connection_settings
      @stubbed || {
        base_url: ENV["TRACCAR_API_BASE_URL"].presence || Rails.application.credentials.dig(:traccar, :api_base_url),
        token: ENV["TRACCAR_API_TOKEN"].presence || Rails.application.credentials.dig(:traccar, :api_token),
        email: ENV["TRACCAR_API_EMAIL"].presence || Rails.application.credentials.dig(:traccar, :api_email),
        password: ENV["TRACCAR_API_PASSWORD"].presence || Rails.application.credentials.dig(:traccar, :api_password)
      }
    end

    def request(method, path, body = nil)
      creds = connection_settings

      raise CredentialsMissing, "Traccar API credentials가 설정되지 않았습니다" if creds[:base_url].blank?

      uri = URI.join(creds[:base_url], path)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method)
      req = klass.new(uri)
      if creds[:token].present?
        req["Authorization"] = "Bearer #{creds[:token]}"
      else
        req.basic_auth(creds[:email], creds[:password])
      end
      if body
        req["Content-Type"] = "application/json"
        req.body = body.to_json
      end

      res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }
      raise "Traccar API #{method} #{path} → #{res.code}" unless res.is_a?(Net::HTTPSuccess)
      res
    end
  end
end
