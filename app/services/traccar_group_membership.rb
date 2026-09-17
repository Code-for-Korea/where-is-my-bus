# RouteBus(배차) 생성/삭제 시 Traccar device의 group 소속을 갱신한다.
# Traccar API에서 device의 group 소속은 device 리소스 자체의 groupId 필드다 — 별도의
# "멤버십" 엔드포인트가 없으므로 GET으로 현재 device 속성을 읽은 뒤 groupId만 바꿔 PUT한다.
class TraccarGroupMembership
  include TraccarApiClient

  NO_GROUP = 0

  class << self
    # 배차(RouteBus) 생성 시 호출. device가 없으면 스킵(성공 취급, 미프로비저닝 상태).
    # route에 group이 없으면 TraccarGroupSync.call로 먼저 확보한다.
    def add(route_bus)
      bus = route_bus.bus
      return Result.new(success: true) unless bus&.traccar_device_id

      route = route_bus.route
      if route.traccar_group_id.blank?
        group_result = TraccarGroupSync.call(route)
        return group_result if group_result.failure?
      end

      set_device_group(bus.traccar_device_id, route.traccar_group_id)
      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarGroupMembership] add #{route_bus.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "group 연결 실패: #{e.message}")
    end

    # 배차 해제(RouteBus 삭제) 시 호출. device가 없으면 스킵(성공 취급).
    def remove(route_bus)
      bus = route_bus.bus
      return Result.new(success: true) unless bus&.traccar_device_id

      set_device_group(bus.traccar_device_id, NO_GROUP)
      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarGroupMembership] remove #{route_bus.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "group 해제 실패: #{e.message}")
    end

    private

    def set_device_group(device_id, group_id)
      device = JSON.parse(request(:get, "/api/devices/#{device_id}").body)
      device["groupId"] = group_id
      request(:put, "/api/devices/#{device_id}", device.deep_symbolize_keys)
    end
  end
end
