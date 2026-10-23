module Integrations
  # Traccar 이벤트 포워딩(event.forward.url) 수신 엔드포인트.
  # Traccar 서버가 Geofence 진입/이탈 같은 이벤트마다 { "event": {...}, "device": {...}, ... } JSON을 POST 한다.
  # 머신 간 통신이므로 ActionController::API 기반(브라우저 제한·CSRF·세션 인증 없음) + 공유 토큰 인증.
  class TraccarEventsController < ActionController::API
    before_action :authenticate_ingest!

    # POST /integrations/traccar/events
    # 인증된 요청은 기록하지 않는 이벤트여도 200으로 ack한다 — 재시도 폭주 방지. 사유는 응답 본문에 담는다.
    def create
      result = StopVisitRecorder.call(params.to_unsafe_h)

      render json: { status: result.status, reason: result.reason }.compact
    end

    private

    def authenticate_ingest!
      provided = request.headers["X-Ingest-Token"].to_s
      expected = ingest_token
      return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

      head :unauthorized
    end

    def ingest_token
      Rails.application.credentials.dig(:traccar, :ingest_token) ||
        ENV["TRACCAR_INGEST_TOKEN"] ||
        (Rails.env.local? ? "dev-traccar-token" : nil)
    end
  end
end
