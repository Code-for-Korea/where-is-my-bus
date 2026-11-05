namespace :traccar do
  # 로컬 Traccar(bin/traccar, compose)의 기본 접속 값. 환경변수가 없을 때 credentials의 원격 서버로 새지 않게 이 작업에서만 채운다.
  local_defaults = {
    "TRACCAR_API_BASE_URL" => "http://localhost:8082",
    "TRACCAR_API_TOKEN" => "dev-traccar-api-token"
  }

  desc "Route/Stop/Bus/RouteStop을 로컬 Traccar에 다시 동기화한다(group → geofence → device → 정류장 연결). bin/traccar reset 뒤에 쓴다"
  task sync: :environment do
    abort "운영 환경에서는 실행하지 않습니다(로컬 개발용)." if Rails.env.production?

    original = local_defaults.keys.to_h { |key| [ key, ENV[key] ] }
    local_defaults.each { |key, value| ENV[key] = value if ENV[key].blank? }
    puts "대상 Traccar: #{ENV["TRACCAR_API_BASE_URL"]}"

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
    run.call("정류장 연결", RouteStop.includes(:route, :stop).all) { |route_stop| TraccarRouteStopLink.link(route_stop) }

    if failures.any?
      puts "\n실패 #{failures.size}건:"
      failures.each { |line| puts "  - #{line}" }
      abort
    end
    puts "완료."
  ensure
    original&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  desc "저장된 traccar_*_id를 비운다. Traccar 데이터를 지웠을 때(bin/traccar reset)만 쓴다 — 남아 있는 Traccar 자원과 중복·충돌될 수 있다"
  task reset_ids: :environment do
    abort "운영 환경에서는 실행하지 않습니다(로컬 개발용)." if Rails.env.production?

    Route.update_all(traccar_group_id: nil)
    Stop.update_all(traccar_geofence_id: nil)
    Bus.update_all(traccar_device_id: nil)
    puts "저장된 traccar_group_id/geofence_id/device_id를 비웠습니다."
  end
end
