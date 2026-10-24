namespace :traccar do
  desc "Route/Stop/Bus/RouteBus를 로컬 Traccar에 한 번에 동기화(group → geofence → device → 배차 연결)"
  task sync: :environment do
    abort "운영 환경에서는 실행하지 않습니다(로컬 개발용)." if Rails.env.production?

    config = Rails.configuration.x.traccar
    abort "Traccar API 접속 정보가 없습니다(config/traccar.yml)." if config.api_base_url.blank?
    puts "대상 Traccar: #{config.api_base_url}"

    failures = []
    run = lambda do |label, records, &sync|
      ok = 0
      records.each do |record|
        result = sync.call(record)
        if result.failure?
          failures << "#{label} ##{record.id}: #{result.error}"
        else
          ok += 1
        end
      end
      puts "#{label}: #{ok}/#{records.size}"
    end

    run.call("group (노선)", Route.all) { |route| TraccarGroupSync.call(route) }
    run.call("geofence (정류장)", Stop.all) { |stop| TraccarGeofenceSync.call(stop) }
    run.call("device (버스)", Bus.all) { |bus| TraccarDeviceSync.call(bus) }
    run.call("배차 연결", RouteBus.includes(:route, :bus).all) { |route_bus| TraccarGroupMembership.add(route_bus) }

    if failures.any?
      puts "\n실패 #{failures.size}건:"
      failures.each { |line| puts "  - #{line}" }
      abort
    end
    puts "완료."
  end

  desc "저장된 traccar_*_id를 비운다. Traccar 데이터를 지웠을 때(bin/traccar reset)만 쓴다 — 남아 있는 Traccar 리소스와 중복·충돌될 수 있다"
  task reset_ids: :environment do
    abort "운영 환경에서는 실행하지 않습니다(로컬 개발용)." if Rails.env.production?

    Route.update_all(traccar_group_id: nil)
    Stop.update_all(traccar_geofence_id: nil)
    Bus.update_all(traccar_device_id: nil)
    puts "저장된 traccar_group_id/geofence_id/device_id를 비웠습니다."
  end
end
