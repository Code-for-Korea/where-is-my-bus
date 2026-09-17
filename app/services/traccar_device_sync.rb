# 버스(Bus) 단위 Traccar device를 생성/갱신/삭제한다.
# device가 있어야 노선 group에 연결(TraccarGroupMembership)될 수 있다.
class TraccarDeviceSync
  include TraccarApiClient

  class << self
    # bus 생성/수정 시 호출. device가 없으면 생성 후 bus.traccar_device_id 저장, 있으면 name 등 갱신.
    def call(bus)
      if bus.traccar_device_id.present?
        update_device(bus.traccar_device_id, bus.license_plate, bus.traccar_unique_id)
      else
        device_id = create_device(bus.license_plate, bus.traccar_unique_id)
        bus.update!(traccar_device_id: device_id)
      end

      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarDeviceSync] #{bus.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "device 동기화 실패: #{e.message}")
    end

    # bus 삭제 시 호출. device가 없으면 스킵(성공 취급).
    def destroy(bus)
      return Result.new(success: true) unless bus.traccar_device_id

      request(:delete, "/api/devices/#{bus.traccar_device_id}")
      Result.new(success: true)
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      Rails.logger.error("[TraccarDeviceSync] destroy #{bus.id}: #{e.class} #{e.message}")
      Result.new(success: false, error: "device 삭제 실패: #{e.message}")
    end

    private

    def create_device(name, unique_id)
      res = request(:post, "/api/devices", { name: name, uniqueId: unique_id })
      JSON.parse(res.body)["id"]
    end

    def update_device(id, name, unique_id)
      request(:put, "/api/devices/#{id}", { id: id, name: name, uniqueId: unique_id })
    end
  end
end
