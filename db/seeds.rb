# 운영에서는 실행하지 않는다. 이 시드는 operator@example.com / password123 계정과 데모 정류장·노선·차량을 만들고,
# 그 자원들을 연결된 Traccar에 실제로 만든다. 새 DB를 만들 때 db:prepare가 시드를 자동 실행하므로(bin/docker-entrypoint)
# 가드가 없으면 첫 배포에서 실서버에 데모 데이터와 알려진 비밀번호의 관리자가 생긴다.
if Rails.env.production? && ENV["ALLOW_PRODUCTION_SEED"] != "1"
  puts "운영 환경에서는 시드를 실행하지 않는다. (정말 필요하면 ALLOW_PRODUCTION_SEED=1)"
  return
end

# 로컬 데모 시드. 여러 번 실행해도 안전하다 (이미 있는 것은 건너뛴다).
# 노선·정류장·차량은 관리자 화면과 같은 등록 서비스를 거치므로 Traccar에도 group·geofence·device가 함께 만들어진다.
# 그래서 Traccar가 떠 있어야 하며, 아직 뜨는 중이면 잠시 재시도한다.

OPERATOR_EMAIL = "operator@example.com".freeze
OPERATOR_PASSWORD = "password123".freeze

# 정류장 좌표는 서로 200~300m 떨어져 있다 (Geofence가 30m 정사각형이라 겹치지 않는다).
STOPS = {
  "고성터미널" => [ 34.9731, 128.3222 ],
  "고성시장"   => [ 34.9751, 128.3246 ],
  "고성병원"   => [ 34.9771, 128.3270 ],
  "고성고등학교" => [ 34.9791, 128.3294 ],
  "고성군청"   => [ 34.9751, 128.3298 ],
  "고성보건소" => [ 34.9731, 128.3326 ]
}.freeze

# 터미널과 병원은 두 노선이 함께 선다. 2번 노선은 시장을 지나가지만 서지 않는다.
ROUTES = {
  "1번 노선" => %w[고성터미널 고성시장 고성병원 고성고등학교],
  "2번 노선" => %w[고성터미널 고성병원 고성군청 고성보건소]
}.freeze

# 차량마다 노선 하나를 배정한다. 운전자는 운행을 시작할 때 노선을 고르지 않고 이 노선으로 운행한다.
BUSES = [
  { license_plate: "경남70가1001", bus_number: "1번", route: "1번 노선" },
  { license_plate: "경남70가1002", bus_number: "2번", route: "2번 노선" }
].freeze

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

puts "== 관리자 계정"
operator = User.find_or_initialize_by(email_address: OPERATOR_EMAIL)
operator.password = OPERATOR_PASSWORD if operator.new_record?
operator.role = :operator
operator.save!

puts "== 정류장"
stops = STOPS.to_h do |name, (lat, lng)|
  stop = Stop.find_by(name: name) || provision!("정류장 #{name}") { StopRegistration.create(name: name, lat: lat, lng: lng) }
  [ name, stop ]
end

puts "== 노선"
ROUTES.each do |route_name, stop_names|
  route = Route.find_by(name: route_name) || provision!("노선 #{route_name}") { RouteRegistration.create(name: route_name) }
  stop_names.each.with_index(1) do |stop_name, sequence|
    next if RouteStop.exists?(route: route, stop: stops.fetch(stop_name))

    provision!("#{route_name} · #{stop_name}") do
      RouteStopRegistration.create(route: route, stop: stops.fetch(stop_name), sequence: sequence)
    end
  end
end

puts "== 차량"
buses = BUSES.map do |attrs|
  route = Route.find_by!(name: attrs[:route])
  bus = Bus.find_by(license_plate: attrs[:license_plate])
  if bus.nil?
    provision!("차량 #{attrs[:license_plate]}") { BusRegistration.create(attrs.slice(:license_plate, :bus_number).merge(route_id: route.id)) }
  elsif bus.route_id != route.id
    provision!("차량 #{attrs[:license_plate]} 노선 배정") { BusRegistration.update(bus, route_id: route.id) }
  else
    bus
  end
end

puts <<~SUMMARY

  시드 완료: 노선 #{Route.count}개, 정류장 #{Stop.count}개, 차량 #{Bus.count}대
    관리자 로그인  #{OPERATOR_EMAIL} / #{OPERATOR_PASSWORD}   (http://localhost:3000/admin)
    승객 화면      http://localhost:3000
  차량:
  #{buses.map { |bus| "  #{bus.license_plate} (#{bus.bus_number}) → #{bus.route.name}  PIN #{bus.pin}  deviceId #{bus.traccar_unique_id}" }.join("\n")}

  운행 시뮬레이션:  docker compose exec rails bin/rails "demo:drive[1번]"
SUMMARY
