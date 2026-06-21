module Integrations
  # Traccar 위치 포워딩(forward.json=true) 수신 엔드포인트.
  # Traccar 서버가 새 위치마다 { "position": {...}, "device": {...} } JSON 을 POST 한다.
  # 머신 간 통신이므로 ActionController::API 기반(브라우저 제한·CSRF·세션 인증 없음) + 공유 토큰 인증.
  class TraccarController < ActionController::API
    before_action :authenticate_ingest!

    # POST /integrations/traccar/positions
    def positions
      unique_id = params.dig(:device, :uniqueId)
      pos       = params[:position] || {}
      lat       = pos[:latitude]
      lng       = pos[:longitude]

      bus = unique_id && Bus.find_by(traccar_unique_id: unique_id)
      # 알 수 없는 단말/좌표 누락은 조용히 무시(ack) — 포워딩 재시도 폭주 방지
      return head :ok if bus.nil? || lat.blank? || lng.blank?

      trip = bus.trips.where(ended_at: nil).order(started_at: :desc).first
      trip ||= bus.trips.create!(started_at: Time.current)

      trip.gps_logs.create!(
        lat: lat,
        lng: lng,
        recorded_at: parse_time(pos[:fixTime] || pos[:deviceTime])
      )

      head :ok
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

    def parse_time(value)
      (value.present? && Time.zone.parse(value.to_s)) || Time.current
    rescue ArgumentError
      Time.current
    end
  end
end
