# 마지막 GPS 수신 이후 TRIP_AUTO_TERMINATE_AFTER(config/initializers/datalogger.rb)가
# 경과한 활성 trip(ended_at: nil)을 자동 종료하는 recurring 잡.
#
# 판정 기준: trip의 최신 GpsLog.recorded_at과 그 버스의 CurrentPosition.recorded_at 중
# 더 최근 값을 "마지막 GPS 수신"으로 본다. 둘 다 없으면(GpsLog 보존 잡 삭제 등) started_at으로 폴백.
# 종료 시 CurrentPosition은 건드리지 않는다 — 다음 운행 판정·지도 표시용 최신값이므로.
class TripAutoTerminatorJob < ApplicationJob
  queue_as :default

  def perform(timeout: TRIP_AUTO_TERMINATE_AFTER)
    active_trips = Trip.where(ended_at: nil)
    return if active_trips.empty?

    cutoff = Time.current - timeout
    latest_gps_log_at = GpsLog.where(trip_id: active_trips.ids).group(:trip_id).maximum(:recorded_at)
    positions = CurrentPosition.where(bus_id: active_trips.map(&:bus_id)).index_by(&:bus_id)

    active_trips.find_each do |trip|
      last_seen_at = [ latest_gps_log_at[trip.id], positions[trip.bus_id]&.recorded_at ].compact.max || trip.started_at
      next if last_seen_at > cutoff

      trip.update!(ended_at: Time.current)
    end
  end
end
