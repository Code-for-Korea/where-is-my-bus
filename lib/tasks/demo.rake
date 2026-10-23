namespace :demo do
  desc "운전자 앱 대신 버스 한 대가 노선을 한 바퀴 도는 것을 흉내낸다. 예: bin/rails 'demo:drive[1번,1번 노선]'"
  task :drive, %i[bus route interval dwell] => :environment do |_task, args|
    abort "사용법: bin/rails 'demo:drive[버스(번호판 또는 번호),노선명,전송간격초,정차초]'" if args[:bus].blank? || args[:route].blank?

    $stdout.sync = true # 파이프·파일로 보낼 때도 진행 상황이 바로 보이게

    bus = Bus.find_by(license_plate: args[:bus]) || Bus.find_by(bus_number: args[:bus])
    abort "버스 '#{args[:bus]}'를 찾을 수 없습니다 (있는 버스: #{Bus.pluck(:license_plate, :bus_number).map { |p, n| "#{p}(#{n})" }.join(", ")})" unless bus

    Demo::BusSimulator.new(
      device_id: bus.traccar_unique_id,
      route_name: args[:route],
      rails_url: ENV.fetch("DEMO_RAILS_URL", "http://localhost:3000"),
      osmand_url: ENV.fetch("TRACCAR_OSMAND_URL", "http://localhost:5055"),
      interval: Float(args[:interval] || 1.0),
      dwell: Float(args[:dwell] || 6)
    ).run
  rescue ArgumentError => e
    abort e.message
  end
end
