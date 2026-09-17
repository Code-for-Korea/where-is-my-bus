# 정류장(Stop) 등록/수정 시 Traccar geofence를 생성/갱신하고, 그 정류장이 속한 노선(Route)의
# group에 연결한다(device 개별 연결이 아니라 group 연결 — group에 배정된 모든 버스에 전파됨).
class TraccarGeofenceSync
  include TraccarApiClient

  SIDE_METERS = 30
  METERS_PER_LAT_DEGREE = 111_320.0

  class << self
    # lat/lng를 중심으로 한 변 side_meters 크기의 정사각형을 WKT POLYGON 문자열로 반환.
    # 위도 1도 ≈ 111.32km 고정 근사 + 경도는 cos(lat) 보정. 30m 규모에서는 이 근사의 오차가 무시 가능한 수준.
    def rectangle_wkt(lat:, lng:, side_meters: SIDE_METERS)
      half = side_meters / 2.0
      dlat = half / METERS_PER_LAT_DEGREE
      dlng = half / (METERS_PER_LAT_DEGREE * Math.cos(lat * Math::PI / 180))

      corners = [
        [ lat - dlat, lng - dlng ],
        [ lat - dlat, lng + dlng ],
        [ lat + dlat, lng + dlng ],
        [ lat + dlat, lng - dlng ],
        [ lat - dlat, lng - dlng ]
      ]

      "POLYGON((#{corners.map { |c| c.join(' ') }.join(', ')}))"
    end

    # stop 생성/수정 시 호출. 좌표가 없으면 스킵(성공 취급).
    def call(stop)
      return Result.new(success: true) unless stop.coordinates?

      route = stop.route
      if route.traccar_group_id.blank?
        group_result = TraccarGroupSync.call(route)
        return group_result if group_result.failure?
      end

      wkt = rectangle_wkt(lat: stop.lat.to_f, lng: stop.lng.to_f)
      name = stop.name

      if stop.traccar_geofence_id.present?
        update_geofence(stop.traccar_geofence_id, name, wkt)
      else
        geofence_id = create_geofence(name, wkt)
        stop.update!(traccar_geofence_id: geofence_id)
      end

      link_group(route.traccar_group_id, stop.traccar_geofence_id)
      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarGeofenceSync] #{stop.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "geofence 동기화 실패: #{e.message}")
    end

    # stop 삭제 시 호출. geofence가 없으면 스킵(성공 취급).
    def destroy(stop)
      return Result.new(success: true) unless stop.traccar_geofence_id

      request(:delete, "/api/geofences/#{stop.traccar_geofence_id}")
      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarGeofenceSync] destroy #{stop.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "geofence 삭제 실패: #{e.message}")
    end

    private

    def create_geofence(name, wkt)
      res = request(:post, "/api/geofences", { name: name, area: wkt })
      JSON.parse(res.body)["id"]
    end

    def update_geofence(id, name, wkt)
      request(:put, "/api/geofences/#{id}", { id: id, name: name, area: wkt })
    end

    def link_group(group_id, geofence_id)
      request(:post, "/api/permissions", { groupId: group_id, geofenceId: geofence_id })
    end
  end
end
