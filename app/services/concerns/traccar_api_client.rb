# frozen_string_literal: true

require "net/http"
require "json"

# Traccar 서비스 객체(TraccarGroupSync/TraccarGroupMembership/TraccarGeofenceSync) 공통 HTTP 클라이언트.
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

  included do
    # 각 서비스 클래스에서 Result를 그대로 참조할 수 있도록 상수를 노출 (예: TraccarGroupSync::Result)
    const_set(:Result, TraccarApiClient::Result) unless const_defined?(:Result, false)
  end

  class_methods do
    # 테스트용: credentials 대신 명시적으로 접속 정보를 주입
    def stub_credentials(base_url:, email:, password:)
      @stubbed = { base_url: base_url, email: email, password: password }
    end

    private

    def request(method, path, body = nil)
      creds = @stubbed || {
        base_url: Rails.application.credentials.dig(:traccar, :api_base_url),
        email: Rails.application.credentials.dig(:traccar, :api_email),
        password: Rails.application.credentials.dig(:traccar, :api_password)
      }

      uri = URI.join(creds[:base_url], path)
      klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put, delete: Net::HTTP::Delete }.fetch(method)
      req = klass.new(uri)
      req.basic_auth(creds[:email], creds[:password])
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
