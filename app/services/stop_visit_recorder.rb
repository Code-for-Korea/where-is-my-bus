# Traccar Geofence 이벤트(event.forward JSON)를 버스의 진행 중인 운행에 정류장 방문 기록으로 남긴다.
# 페이로드 형식은 docs/design-event-driven-rewrite.md 6절 참고.
#
# 기록하지 않는 이벤트는 오류가 아니라 status: :ignored와 사유(reason)로 돌려준다 —
# 호출 쪽(컨트롤러)이 항상 ack해서 Traccar의 재시도 폭주를 막기 위해서다.
class StopVisitRecorder
  ENTER = "geofenceEnter".freeze
  EXIT  = "geofenceExit".freeze

  Result = Struct.new(:status, :reason, :visit, keyword_init: true) do
    def recorded? = status == :recorded
    def ignored? = status == :ignored
  end

  def self.call(payload)
    new(payload).call
  end

  def initialize(payload)
    @payload = payload.to_h.deep_stringify_keys
  end

  def call
    return ignored(:unsupported_type) unless [ ENTER, EXIT ].include?(type)
    return ignored(:invalid_payload) unless event_id.present? && event_time && geofence_id.present? && unique_id.present?

    bus = Bus.find_by(traccar_unique_id: unique_id)
    return ignored(:unknown_device) unless bus

    stop = Stop.find_by(traccar_geofence_id: geofence_id)
    return ignored(:unknown_geofence) unless stop

    trip = bus.active_trip
    return ignored(:no_active_trip) unless trip
    return ignored(:before_trip_start) if event_time < trip.started_at
    return ignored(:stop_not_on_route) unless trip.route.route_stops.exists?(stop_id: stop.id)

    type == ENTER ? record_enter(trip, stop) : record_exit(trip, stop)
  rescue ActiveRecord::RecordNotUnique
    # 같은 이벤트가 동시에 두 번 도착한 경우 — 유니크 인덱스가 막아 준다.
    ignored(:duplicate)
  end

  private

  def record_enter(trip, stop)
    return ignored(:duplicate) if StopVisit.exists?(entered_event_id: event_key)
    # 같은 정류장에서 아직 나가지 않았는데 다시 진입 이벤트가 오면 이상 상황이므로 기록하지 않는다.
    return ignored(:already_inside) if trip.stop_visits.open.exists?(stop_id: stop.id)

    visit = trip.stop_visits.create!(stop: stop, entered_at: event_time, entered_event_id: event_key)
    Result.new(status: :recorded, visit: visit)
  end

  def record_exit(trip, stop)
    return ignored(:duplicate) if StopVisit.exists?(exited_event_id: event_key)

    # 운행을 정류장 안에서 시작하면 진입 이벤트가 없으므로 열린 방문 기록이 없을 수 있다 (개선점 20번).
    visit = trip.stop_visits.open.where(stop_id: stop.id).latest_first.first
    return ignored(:no_open_visit) unless visit

    visit.update!(exited_at: event_time, exited_event_id: event_key)
    Result.new(status: :recorded, visit: visit)
  end

  def ignored(reason)
    Rails.logger.info("[StopVisitRecorder] ignored #{type.inspect} event=#{event_id.inspect} device=#{unique_id.inspect}: #{reason}")
    Result.new(status: :ignored, reason: reason)
  end

  def type = @payload.dig("event", "type")
  def event_id = @payload.dig("event", "id")
  def geofence_id = @payload.dig("event", "geofenceId")
  def unique_id = @payload.dig("device", "uniqueId")

  def event_time
    return @event_time if defined?(@event_time)

    @event_time = Time.iso8601(@payload.dig("event", "eventTime").to_s).utc
  rescue ArgumentError
    @event_time = nil
  end

  # Traccar 이벤트 ID는 Traccar DB가 초기화되면 1부터 다시 시작하므로 시각과 함께 쓴다.
  def event_key
    "#{event_id}@#{event_time.iso8601(3)}"
  end
end
