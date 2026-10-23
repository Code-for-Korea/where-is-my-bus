# 운행 시작/종료에 맞춰 버스의 Traccar device를 노선 group으로 옮기거나 group에서 뺀다.
# Traccar API에서 device의 group 소속은 device 리소스 자체의 groupId 필드다 — 별도의
# "멤버십" 엔드포인트가 없으므로 GET으로 현재 device 속성을 읽은 뒤 groupId만 바꿔 PUT한다.
# device는 group을 하나만 가질 수 있어, 새 노선으로 옮기면 이전 소속은 자연히 덮어써진다.
class TraccarDeviceGroup
  include TraccarApiClient

  NO_GROUP = 0

  class << self
    # 운행 시작 시 호출. device나 노선 group이 없으면 이벤트를 받을 수 없으므로 실패.
    def assign(bus, route)
      return Result.new(success: false, error: "Traccar 차량이 없습니다") if bus.traccar_device_id.blank?
      return Result.new(success: false, error: "Traccar 노선이 없습니다") if route.traccar_group_id.blank?

      set_group(bus.traccar_device_id, route.traccar_group_id)
      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarDeviceGroup] assign #{bus.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "Traccar에서 차량을 노선에 배정하지 못했습니다: #{e.message}")
    end

    # 운행 종료 시 호출. device가 없으면 뺄 것이 없으므로 스킵(성공 취급).
    def clear(bus)
      return Result.new(success: true) if bus.traccar_device_id.blank?

      set_group(bus.traccar_device_id, NO_GROUP)
      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarDeviceGroup] clear #{bus.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "Traccar에서 차량의 노선 배정을 풀지 못했습니다: #{e.message}")
    end

    private

    def set_group(device_id, group_id)
      device = JSON.parse(request(:get, "/api/devices/#{device_id}").body)
      device["groupId"] = group_id
      request(:put, "/api/devices/#{device_id}", device.deep_symbolize_keys)
    end
  end
end
