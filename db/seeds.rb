# 기획안("내 버스는 언제 올까?") 기준 샘플 데이터. 멱등하게 작성한다.

gyeongnam = Region.find_or_create_by!(name: "경상남도") { |r| r.position = 1 }
jeonnam   = Region.find_or_create_by!(name: "전라남도") { |r| r.position = 2 }

yokji = Area.find_or_create_by!(region: gyeongnam, name: "통영시 욕지도") { |a| a.position = 1 }
jiri  = Area.find_or_create_by!(region: jeonnam,   name: "지리산")       { |a| a.position = 1 }

route35 = Route.find_or_create_by!(area: yokji, name: "35번") do |r|
  r.headway_minutes = 60
  r.likes_count = 2_345
  r.position = 1
end

stop_names = [
  "욕지도 정류장 시작", "욕지도 선착장", "욕지도 선착장 동부",
  "욕지도 정류장 4번", "욕지도 정류장 5번", "욕지도 정류장 6번",
  "욕지도 정류장 7번", "욕지도 정류장", "욕지도 정류장 종점"
]
stop_names.each_with_index do |name, i|
  Stop.find_or_create_by!(route: route35, position: i + 1) { |s| s.name = name }
end

Bus.find_or_create_by!(area: yokji, license_plate: "경남 70바 1234") { |b| b.pin = "1234" }

puts "Seed 완료: Region #{Region.count}, Area #{Area.count}, Route #{Route.count}, Stop #{Stop.count}, Bus #{Bus.count}"
