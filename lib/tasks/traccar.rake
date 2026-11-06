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

  desc "Traccar 웹 화면용 관리자 계정을 만든다(서비스 토큰 사용, 이미 있으면 건너뜀). TRACCAR_ADMIN_EMAIL, 비밀번호는 TRACCAR_ADMIN_PASSWORD 또는 입력 프롬프트"
  task create_admin: :environment do
    # 비밀번호는 인자로 받지 않는다(셸 기록·ps에 남는다). 환경변수는 한 번만 쓰고 지운다.
    email = ENV["TRACCAR_ADMIN_EMAIL"].presence
    abort "TRACCAR_ADMIN_EMAIL을 지정하세요. 예: TRACCAR_ADMIN_EMAIL=me@example.org bin/rails traccar:create_admin" unless email

    password = ENV.delete("TRACCAR_ADMIN_PASSWORD").presence
    if password.nil?
      abort "비밀번호는 TRACCAR_ADMIN_PASSWORD로 주거나 터미널(TTY)에서 실행해 입력하세요." unless $stdin.tty?

      require "io/console"
      print "Traccar 관리자 비밀번호: "
      password = $stdin.noecho(&:gets).to_s.chomp
      puts
    end

    # 운영은 컨테이너의 환경변수(TRACCAR_API_*)를 그대로 쓴다. 로컬 개발에서만 기본값을 채워 credentials의 원격 서버로 새지 않게 한다.
    original = local_defaults.keys.to_h { |key| [ key, ENV[key] ] }
    unless Rails.env.production?
      local_defaults.each { |key, value| ENV[key] = value if ENV[key].blank? }
    end
    puts "대상 Traccar: #{ENV["TRACCAR_API_BASE_URL"].presence || "(credentials)"}"

    begin
      if TraccarAdminUser.exists?(email)
        puts "이미 있는 계정입니다(변경하지 않았습니다): #{email}"
      else
        result = TraccarAdminUser.call(email: email, password: password)
        abort result.error if result.failure?

        puts "관리자 계정을 만들었습니다: #{email}"
      end
    rescue *TraccarApiClient::RESCUED_ERRORS => e
      abort "Traccar 관리자 계정 확인 실패: #{e.message}"
    end
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
