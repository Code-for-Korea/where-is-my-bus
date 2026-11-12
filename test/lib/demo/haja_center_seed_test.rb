require "test_helper"

# 하자센터 시연 시드의 멱등성·지역 지정·Traccar 실패 시 롤백을 검증한다.
# 시드는 정류장·노선·정차·차량을 모두 등록 서비스(*Registration)로 만들므로 Traccar API를 WebMock으로 스텁한다.
class Demo::HajaCenterSeedTest < ActiveSupport::TestCase
  JSON_HEADERS = { "Content-Type" => "application/json" }.freeze

  setup do
    # 지역은 regions:import로 별도 적재돼야 하는 대상이므로 픽스처를 고치지 않고 여기서 만든다.
    seoul = Region.find_or_create_by!(code: "1100000000") do |r|
      r.name = "서울특별시"
      r.kind = "시도"
      r.level = 1
    end
    @region = Region.find_or_create_by!(code: Demo::HajaCenterSeed::REGION_CODE) do |r|
      r.name = "영등포구"
      r.kind = "시군구"
      r.level = 2
      r.parent = seoul
    end

    stub_traccar_credentials(
      TraccarGeofenceSync, TraccarGroupSync, TraccarRouteStopLink, TraccarDeviceSync, TraccarDeviceGroup
    )
  end

  test "두 번 실행해도 정류장·노선·정차·차량 수가 늘지 않는다" do
    stub_happy_traccar

    capture_io { Demo::HajaCenterSeed.new.run }
    first = counts

    capture_io { Demo::HajaCenterSeed.new.run }

    assert_equal first, counts
  end

  test "모든 시연 정류장의 지역은 영등포구(1156000000)다" do
    stub_happy_traccar

    capture_io { Demo::HajaCenterSeed.new.run }

    assert_equal [ @region.id ],
                 Stop.where(name: Demo::HajaCenterSeed::STOPS.keys).pluck(:region_id).uniq
  end

  test "Traccar 호출이 실패하면 새 레코드가 남지 않는다" do
    stub_request(:post, "#{TRACCAR_API}/api/geofences").to_return(status: 500, body: "boom")
    seed = Demo::HajaCenterSeed.new

    # 시드는 Traccar 연동 실패를 최대 30회 재시도하므로 sleep을 무효화해 빠르게 끝내고 raise에 도달하게 한다.
    assert_no_difference -> { Stop.count } do
      assert_no_difference -> { Route.count } do
        assert_no_difference -> { RouteStop.count } do
          assert_no_difference -> { Bus.count } do
            with_no_sleep(seed) do
              assert_raises(RuntimeError) { capture_io { seed.run } }
            end
          end
        end
      end
    end
  end

  private

  # 시드가 거치는 Traccar 엔드포인트 전부를 성공 응답으로 스텁한다.
  # geofence 5개, group 1개, permission(정차) 5개, device 1개 + 노선 group 이동(GET/PUT).
  def stub_happy_traccar
    stub_request(:post, "#{TRACCAR_API}/api/geofences")
      .to_return(Demo::HajaCenterSeed::STOPS.size.times.map do |i|
        { status: 200, body: { id: 770 + i }.to_json, headers: JSON_HEADERS }
      end)
    stub_request(:post, "#{TRACCAR_API}/api/groups")
      .to_return(status: 200, body: { id: 50 }.to_json, headers: JSON_HEADERS)
    stub_request(:post, "#{TRACCAR_API}/api/permissions").to_return(status: 204, body: "")
    stub_request(:post, "#{TRACCAR_API}/api/devices")
      .to_return(status: 200, body: { id: 60 }.to_json, headers: JSON_HEADERS)
    stub_device_group_move(60, to_group_id: 50)
  end

  # minitest 6에는 minitest/mock이 없어서(seed_test.rb 참고) sleep을 잠깐 덮어쓴다.
  def with_no_sleep(seed)
    seed.define_singleton_method(:sleep) { |_seconds| }
    yield
  ensure
    seed.singleton_class.send(:remove_method, :sleep)
  end

  def counts
    [ Stop.count, Route.count, RouteStop.count, Bus.count ]
  end
end
