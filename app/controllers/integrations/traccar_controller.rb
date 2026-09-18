module Integrations
  # Traccar 위치 포워딩(forward.json=true) 수신 엔드포인트.
  # Traccar 서버가 새 위치마다 { "position": {...}, "device": {...} } JSON 을 POST 한다.
  # 머신 간 통신이므로 ActionController::API 기반(브라우저 제한·CSRF·세션 인증 없음) + 공유 토큰 인증.
  class TraccarController < ActionController::API
    MAX_REGISTER_ATTEMPTS = 5
    REGISTER_LOCKOUT_WINDOW = 15.minutes

    before_action :authenticate_ingest!, only: :positions

    # POST /integrations/traccar/register
    # 운전자 앱 온보딩: PIN → { traccarServerUrl, deviceId }. 브루트포스 방지를 위해 IP당 시도 횟수 제한.
    # PIN은 1회용 — 최초 등록 성공 시 pin_registered_at을 찍어 소모 처리한다. PIN이 유출돼도
    # 이미 등록된 기기가 있으면 다른 기기가 같은 PIN으로 추가 등록할 수 없다(기기분실/교체는
    # 운영자가 admin에서 PIN을 재발급하는 것으로 처리 — Bus#regenerate_pin!).
    def register
      return render json: { error: "too_many_attempts" }, status: :too_many_requests if register_locked_out?

      bus = Bus.active.find_by(pin: params[:pin].to_s)
      if bus.nil?
        Rails.cache.increment(register_rate_limit_key, 1, expires_in: REGISTER_LOCKOUT_WINDOW)
        return render json: { error: "invalid_pin" }, status: :unauthorized
      end

      # 조건부 UPDATE 한 줄로 "미등록 확인"과 "소모 처리"를 원자화 — 동시 요청 경쟁 상태 방지.
      consumed = Bus.where(id: bus.id, pin_registered_at: nil)
                    .update_all(pin_registered_at: Time.current)
      return render json: { error: "pin_already_used" }, status: :conflict if consumed.zero?

      Rails.cache.delete(register_rate_limit_key)
      render json: { traccarServerUrl: traccar_server_url, deviceId: bus.traccar_unique_id }
    end

    # GET /integrations/traccar/routes?deviceId=...
    # driver_app 메인화면용 버스번호 + 노선/정류장 + 다음 정류장 ETA를 한 번에 묶어서 응답.
    # 후순위 기능 — Route에 "활성" 개념이 아직 없어 첫 노선(position순)을 반환.
    def routes
      bus = Bus.find_by(traccar_unique_id: params[:deviceId].to_s)
      return render json: { error: "unknown_device" }, status: :not_found if bus.nil?

      route = bus.routes.first
      return render json: { error: "no_route" }, status: :not_found if route.nil?

      next_stop = RouteProgress.new(bus).next_stop_eta(route)

      render json: {
        busNumber: bus.bus_number.to_s.delete("번"),
        routeName: route.name,
        stops: route.stops.map { |s| { name: s.name, lat: s.lat, lng: s.lng, avgTravelSeconds: s.avg_travel_seconds } },
        nextStop: next_stop && { name: next_stop[:stop].name, etaMinutes: next_stop[:eta_minutes] }
      }
    end

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

    # 배포(지역/국가)별 Traccar 서버 주소 — 운전자 앱이 위치를 직접 전송할 대상.
    # ponytail: 로컬 기본값은 실제 배포 전까지 기존 테스트 서버로 임시 고정. credentials/ENV 세팅되면 그쪽이 우선.
    def traccar_server_url
      Rails.application.credentials.dig(:traccar, :server_url) ||
        ENV["TRACCAR_SERVER_URL"] ||
        (Rails.env.local? ? "http://yehyunserver.iptime.org:5055" : nil)
    end

    def register_rate_limit_key
      "traccar_register_attempts:#{request.remote_ip}"
    end

    def register_locked_out?
      Rails.cache.read(register_rate_limit_key).to_i >= MAX_REGISTER_ATTEMPTS
    end

    def parse_time(value)
      (value.present? && Time.zone.parse(value.to_s)) || Time.current
    rescue ArgumentError
      Time.current
    end
  end
end
