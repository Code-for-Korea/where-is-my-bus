module Integrations
  # 운전자 앱(driver_app) 온보딩·노선 조회 엔드포인트.
  # 머신 간 통신이므로 ActionController::API 기반(브라우저 제한·CSRF·세션 인증 없음).
  # GPS는 앱이 Traccar로 직접 보내고, Geofence 이벤트는 TraccarEventsController가 받는다.
  # 운행 시작·종료는 TripsController.
  class TraccarController < ActionController::API
    MAX_REGISTER_ATTEMPTS = 5
    REGISTER_LOCKOUT_WINDOW = 15.minutes

    # POST /integrations/traccar/register
    # 운전자 앱 온보딩: PIN → { traccarServerUrl, deviceId }. 브루트포스 방지를 위해 IP당 시도 횟수 제한.
    # PIN은 1회용 — 최초 등록 성공 시 pin_registered_at을 찍어 소모 처리한다. PIN이 유출돼도
    # 이미 등록된 기기가 있으면 다른 기기가 같은 PIN으로 추가 등록할 수 없다(기기분실/교체는
    # 운영자가 admin에서 PIN을 재발급하는 것으로 처리 — Bus#regenerate_pin!).
    def register
      return render json: { error: "too_many_attempts" }, status: :too_many_requests if register_locked_out?

      bus = Bus.find_by(pin: params[:pin].to_s)
      if bus.nil?
        Rails.cache.increment(register_rate_limit_key, 1, expires_in: REGISTER_LOCKOUT_WINDOW)
        return render json: { error: "invalid_pin" }, status: :unauthorized
      end

      # 조건부 UPDATE 한 줄로 "미등록 확인"과 "소모 처리"를 원자화 — 동시 요청 경쟁 상태 방지.
      consumed = Bus.where(id: bus.id, pin_registered_at: nil)
                    .update_all(pin_registered_at: Time.current)
      return render json: { error: "pin_already_used" }, status: :conflict if consumed.zero?

      Rails.cache.delete(register_rate_limit_key)
      render json: { traccarServerUrl: traccar_server_url, deviceId: bus.traccar_unique_id }.merge(bus_summary(bus))
    end

    # GET /integrations/traccar/bus?deviceId=...
    # 앱 메인 화면용: 이 차량의 번호, 관리자가 배정한 노선(정류장 포함), 진행 중인 운행(있으면).
    def bus
      bus = Bus.find_by(traccar_unique_id: params[:deviceId].to_s)
      return render json: { error: "unknown_device" }, status: :not_found if bus.nil?

      render json: bus_summary(bus).merge(activeTrip: TripSerializer.call(bus.active_trip))
    end

    private

    # 배정된 노선이 없으면 route는 null이다 — 앱은 "배정된 노선이 없습니다"를 안내한다.
    def bus_summary(bus)
      route = bus.route
      {
        busNumber: bus.bus_number.to_s.delete("번"),
        licensePlate: bus.license_plate,
        route: route && {
          id: route.id, name: route.name,
          stops: route.route_stops.includes(:stop).map { |rs| { name: rs.stop.name, lat: rs.stop.lat.to_f, lng: rs.stop.lng.to_f } }
        }
      }
    end

    # 운전자 앱이 위치를 직접 전송할 Traccar 서버(OsmAnd 수신) 주소. 환경변수가 credentials보다 우선한다.
    # 로컬 기본값은 localhost — 같은 Wi-Fi의 실제 폰으로 시험하려면 TRACCAR_SERVER_URL을 PC의 LAN 주소로 지정한다.
    def traccar_server_url
      ENV["TRACCAR_SERVER_URL"].presence ||
        Rails.application.credentials.dig(:traccar, :server_url) ||
        (Rails.env.local? ? "http://localhost:5055" : nil)
    end

    def register_rate_limit_key
      "traccar_register_attempts:#{request.remote_ip}"
    end

    def register_locked_out?
      Rails.cache.read(register_rate_limit_key).to_i >= MAX_REGISTER_ATTEMPTS
    end
  end
end
