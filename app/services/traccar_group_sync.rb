# route(노선) 단위 Traccar group을 생성/갱신/삭제한다.
# group이 있어야 geofence 연결(TraccarRouteStopLink)과 device 이동(TraccarDeviceGroup)이 가능하다.
class TraccarGroupSync
  include TraccarApiClient

  class << self
    # route 생성/수정 시 호출. group이 없으면 생성 후 route.traccar_group_id 저장, 있으면 name 갱신.
    def call(route)
      if route.traccar_group_id.present?
        update_group(route.traccar_group_id, route.name)
      else
        group_id = create_group(route.name)
        route.update!(traccar_group_id: group_id)
      end

      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarGroupSync] #{route.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "Traccar 노선 동기화 실패: #{e.message}")
    end

    # route 삭제 시 호출. group이 없으면 스킵(성공 취급).
    def destroy(route)
      return Result.new(success: true) unless route.traccar_group_id

      request(:delete, "/api/groups/#{route.traccar_group_id}")
      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarGroupSync] destroy #{route.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "Traccar 노선 삭제 실패: #{e.message}")
    end

    private

    def create_group(name)
      res = request(:post, "/api/groups", { name: name })
      JSON.parse(res.body)["id"]
    end

    def update_group(id, name)
      request(:put, "/api/groups/#{id}", { id: id, name: name })
    end
  end
end
