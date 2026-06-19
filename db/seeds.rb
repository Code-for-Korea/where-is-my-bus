# 승객 웹 개발용 테스트 데이터 (Area 구조 유지 + GPS 추적 포함)
# find_or_create_by! 로 idempotent 보장

puts "Seeding regions..."
region = Region.find_or_initialize_by(slug: "goseong")
region.name    = "경남 고성군"
region.name_en = "Goseong County, South Gyeongsang"
region.save!

puts "Seeding areas..."
area = Area.find_or_create_by!(region: region, name: "고성군") { |a| a.position = 1 }

puts "Seeding buses..."
bus = Bus.find_or_create_by!(license_plate: "경남 70 가 1234") do |b|
  b.area       = area
  b.pin        = "1234"
  b.bus_number = "1번"
  b.status     = "active"
end

puts "Seeding pin codes..."
PinCode.find_or_create_by!(code: "GOSEONG-1234") do |p|
  p.bus    = bus
  p.active = true
end

puts "Seeding routes..."
route = Route.find_or_create_by!(name: "고성↔통영 1번 노선") do |r|
  r.area = area
  r.bus  = bus
end

puts "Seeding stops..."
stops_data = [
  { sequence: 1, name: "고성터미널",   name_en: "Goseong Terminal",       lat: 34.9731, lng: 128.3227, avg_travel_seconds: nil },
  { sequence: 2, name: "고성시장",     name_en: "Goseong Market",         lat: 34.9712, lng: 128.3198, avg_travel_seconds: 180 },
  { sequence: 3, name: "거류면사무소", name_en: "Georyu Township Office", lat: 34.9580, lng: 128.3105, avg_travel_seconds: 420 },
  { sequence: 4, name: "당동리",       name_en: "Dangdong-ri",            lat: 34.9430, lng: 128.3010, avg_travel_seconds: 360 },
  { sequence: 5, name: "하이면사무소", name_en: "Hai Township Office",    lat: 34.9281, lng: 128.2890, avg_travel_seconds: 480 },
  { sequence: 6, name: "덕명리",       name_en: "Deongmyeong-ri",         lat: 34.9150, lng: 128.2750, avg_travel_seconds: 360 },
  { sequence: 7, name: "용호리",       name_en: "Yongho-ri",              lat: 34.9020, lng: 128.2610, avg_travel_seconds: 420 },
  { sequence: 8, name: "통영터미널",   name_en: "Tongyeong Terminal",     lat: 34.8545, lng: 128.4330, avg_travel_seconds: 900 }
]

stops_data.each do |data|
  stop = Stop.find_or_initialize_by(route: route, sequence: data[:sequence])
  stop.assign_attributes(
    name:               data[:name],
    name_en:            data[:name_en],
    lat:                data[:lat],
    lng:                data[:lng],
    avg_travel_seconds: data[:avg_travel_seconds]
  )
  stop.save!
end

puts "Seeding trips & GPS logs..."
trip = Trip.find_or_create_by!(bus: bus, ended_at: nil) do |t|
  t.started_at = 2.hours.ago
end

if trip.gps_logs.empty?
  [
    { lat: 34.9530, lng: 128.3060, recorded_at: 8.minutes.ago },
    { lat: 34.9510, lng: 128.3040, recorded_at: 6.minutes.ago },
    { lat: 34.9490, lng: 128.3025, recorded_at: 4.minutes.ago },
    { lat: 34.9470, lng: 128.3015, recorded_at: 2.minutes.ago },
    { lat: 34.9450, lng: 128.3012, recorded_at: 30.seconds.ago }
  ].each { |pos| GpsLog.create!(trip: trip, **pos) }
end

puts "Done! Region #{Region.count} / Area #{Area.count} / Bus #{Bus.count} / Route #{Route.count} / Stop #{Stop.count} / GpsLog #{GpsLog.count}"
