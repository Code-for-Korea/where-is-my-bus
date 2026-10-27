namespace :demo do
  desc "운전자 앱 대신 버스 한 대가 배정된 노선을 한 바퀴 도는 것을 흉내낸다. 예: bin/rails 'demo:drive[1번]'"
  task :drive, %i[bus interval dwell] => :environment do |_task, args|
    abort "사용법: bin/rails 'demo:drive[버스(번호판 또는 번호),전송간격초,정차초]'" if args[:bus].blank?

    $stdout.sync = true # 파이프·파일로 보낼 때도 진행 상황이 바로 보이게

    # 위치 시각은 1초 단위로 항상 앞으로 가야 한다. 1초보다 자주 보내면 시각이 실제 시간보다 빨리 앞서가고,
    # 곧바로 다시 실행했을 때 앞 실행의 마지막 시각보다 과거 시각이 되어 Traccar가 그 위치를 건너뛴다.
    interval = Float(args[:interval] || 1.0)
    abort "전송 간격은 1초 이상이어야 합니다 (위치 시각이 실제 시간보다 앞서가면 연속 실행 때 이벤트가 사라집니다)." if interval < 1.0

    bus = Bus.find_by(license_plate: args[:bus]) || Bus.find_by(bus_number: args[:bus])
    abort "버스 '#{args[:bus]}'를 찾을 수 없습니다 (있는 버스: #{Bus.pluck(:license_plate, :bus_number).map { |p, n| "#{p}(#{n})" }.join(", ")})" unless bus

    Demo::BusSimulator.new(
      device_id: bus.traccar_unique_id,
      rails_url: ENV.fetch("DEMO_RAILS_URL", "http://localhost:3000"),
      osmand_url: ENV.fetch("TRACCAR_OSMAND_URL", "http://localhost:5055"),
      interval: interval,
      dwell: Float(args[:dwell] || 6)
    ).run
  rescue ArgumentError => e
    abort e.message
  end
end
