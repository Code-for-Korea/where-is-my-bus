# 버스 생성/수정/삭제 + Traccar device 동기화 + 배정된 노선의 Traccar group 맞추기.
# 차량에 노선을 배정하거나 바꾸면 기기를 그 노선의 group으로 옮기고, 배정을 풀면 group에서 뺀다.
# 그래서 운전자의 운행 시작·종료는 Traccar를 부르지 않는다 (docs/design-event-driven-rewrite.md).
class BusRegistration < TraccarRegistration
  manages Bus, with: TraccarDeviceSync

  class << self
    private

    def sync(bus)
      route_changed = bus.saved_change_to_route_id?

      result = TraccarDeviceSync.call(bus)
      return result if result.failure?

      if bus.route
        TraccarDeviceGroup.assign(bus, bus.route)
      elsif route_changed
        TraccarDeviceGroup.clear(bus)
      else
        result
      end
    end
  end
end
