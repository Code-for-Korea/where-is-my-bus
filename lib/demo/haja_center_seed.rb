module Demo
  # 하자센터(서울 영등포구) 시연 시드. 여러 번 실행해도 안전하다 (이미 있는 것은 건너뛰거나 필요한 값만 고친다).
  # 노선·정류장·차량은 관리자 화면과 같은 등록 서비스를 거치므로 Traccar에도 group·geofence·device가 함께 만들어진다.
  # Demo::Seed와 달리 운영에서도 실행할 수 있다 (지역은 만들지 않고 이미 적재된 영등포구를 쓴다).
  class HajaCenterSeed
    # 서울특별시 영등포구 (level 2). regions:import로 미리 적재돼 있어야 한다.
    REGION_CODE = "1156000000".freeze

    ROUTE_NAME = "하자센터 시연 노선".freeze

    BUS_LICENSE_PLATE = "서울70사1001".freeze
    BUS_NUMBER = "하자01".freeze

    # 정류장 좌표는 OSM(OpenStreetMap) 노드에서 가져왔다. 출처는 아래 주석의 노드 permalink.
    # 영등포역 주변이라 지오펜스(30m 정사각형)가 겹치지 않도록 서로 수백 m씩 떨어져 있다.
    STOPS = {
      # https://www.openstreetmap.org/node/12512226846
      "영동초교"   => [ 37.5252508, 126.9068323 ],
      # https://www.openstreetmap.org/node/12534076733
      "신화병원"   => [ 37.5244724, 126.9053251 ],
      # https://www.openstreetmap.org/node/12534076765
      "영등포시장" => [ 37.5215029, 126.9049984 ],
      # https://www.openstreetmap.org/node/357951991
      "영등포역"   => [ 37.5168407, 126.9074712 ],
      # https://www.openstreetmap.org/node/357894954
      "영등포구청" => [ 37.5253315, 126.8964059 ]
    }.freeze

    # 단방향 순환 노선의 정차 순서.
    ROUTE_STOPS = %w[영동초교 신화병원 영등포시장 영등포역 영등포구청].freeze

    def run
      puts "== 지역"
      region = ensure_region

      puts "== 정류장"
      stops = provision_stops(region)

      puts "== 노선"
      route = Route.find_by(name: ROUTE_NAME) || provision!("노선 #{ROUTE_NAME}") { RouteRegistration.create(name: ROUTE_NAME) }
      ROUTE_STOPS.each.with_index(1) do |stop_name, sequence|
        next if RouteStop.exists?(route: route, stop: stops.fetch(stop_name))

        provision!("#{ROUTE_NAME} · #{stop_name}") do
          RouteStopRegistration.create(route: route, stop: stops.fetch(stop_name), sequence: sequence)
        end
      end

      puts "== 차량"
      bus = provision_bus(route)

      puts <<~SUMMARY

        하자센터 시연 시드 완료: 노선 #{Route.count}개, 정류장 #{Stop.count}개, 차량 #{Bus.count}대
          노선  #{route.name}
          차량  #{bus.license_plate} (#{bus.bus_number})  PIN #{bus.pin}  deviceId #{bus.traccar_unique_id}

        운행 시뮬레이션:  bin/rails "demo:drive[#{bus.license_plate}]"
      SUMMARY
    end

    private

    # 시연 지역(서울 영등포구)을 코드로 찾는다. 만들지 않는다 — 지역은 regions:import로 별도 적재된다.
    def ensure_region
      Region.find_by(code: REGION_CODE) ||
        raise("지역 코드 #{REGION_CODE}(서울특별시 영등포구)를 찾을 수 없습니다. " \
              "먼저 bin/rails \"regions:import[CSV 경로]\"로 지역을 적재하세요.")
    end

    def provision_stops(region)
      STOPS.to_h do |name, (lat, lng)|
        stop = Stop.find_by(name: name) || provision!("정류장 #{name}") { StopRegistration.create(name: name, lat: lat, lng: lng, region: region) }
        [ name, stop ]
      end
    end

    def provision_bus(route)
      bus = Bus.find_by(license_plate: BUS_LICENSE_PLATE)
      if bus.nil?
        provision!("차량 #{BUS_LICENSE_PLATE}") do
          BusRegistration.create(license_plate: BUS_LICENSE_PLATE, bus_number: BUS_NUMBER, route_id: route.id)
        end
      elsif bus.route_id != route.id
        provision!("차량 #{BUS_LICENSE_PLATE} 노선 배정") { BusRegistration.update(bus, route_id: route.id) }
      else
        bus
      end
    end

    # 등록 서비스를 실행하고, Traccar 연동 실패(아직 기동 중일 수 있음)는 잠시 후 다시 시도한다.
    def provision!(label)
      attempts = 30
      loop do
        result = yield
        return result.record if result.success?
        raise "#{label} 실패: #{result.error}" unless result.error.include?("실패") && (attempts -= 1).positive?

        puts "  #{label}: Traccar 연결을 기다리는 중... (#{result.error})"
        sleep 2
      end
    end
  end
end
