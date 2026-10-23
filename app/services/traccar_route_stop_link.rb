# 노선별 정차(RouteStop) 생성/삭제 시 그 정류장의 Traccar geofence를 노선 group에 연결/해제한다.
# group에 연결된 geofence의 이벤트는 그 group에 속한 device에게만 전달된다.
# 한 정류장이 여러 노선에 속하면 같은 geofence가 여러 group에 연결된다.
class TraccarRouteStopLink
  include TraccarApiClient

  class << self
    # route_stop 생성 시 호출. group 또는 geofence가 아직 없으면 연결할 수 없으므로 실패.
    def link(route_stop)
      ids = ids_for(route_stop)
      return Result.new(success: false, error: "Traccar 노선 연결 실패: Traccar 노선 또는 정류장 영역이 없습니다") unless ids

      request(:post, "/api/permissions", ids)
      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarRouteStopLink] link #{route_stop.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "정류장 영역 연결 실패: #{e.message}")
    end

    # route_stop 삭제 시 호출. 연결 대상이 이미 없으면 스킵(성공 취급).
    def unlink(route_stop)
      ids = ids_for(route_stop)
      return Result.new(success: true) unless ids

      request(:delete, "/api/permissions", ids)
      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarRouteStopLink] unlink #{route_stop.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "정류장 영역 연결 해제 실패: #{e.message}")
    end

    private

    def ids_for(route_stop)
      group_id = route_stop.route.traccar_group_id
      geofence_id = route_stop.stop.traccar_geofence_id
      return nil if group_id.blank? || geofence_id.blank?

      { groupId: group_id, geofenceId: geofence_id }
    end
  end
end
