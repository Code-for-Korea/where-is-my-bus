require "test_helper"

class Demo::SeedTest < ActiveSupport::TestCase
  test "db/seeds.rb는 아무것도 만들지 않는다 (운영의 db:prepare가 데이터를 만들지 않는다)" do
    before = counts

    load Rails.root.join("db/seeds.rb")

    assert_equal before, counts
  end

  test "운영 환경에서는 데모 데이터를 만들지 않고 종료한다" do
    before = counts

    # minitest 6에는 minitest/mock이 없어서 production?만 잠깐 덮어쓴다.
    Rails.env.define_singleton_method(:production?) { true }
    begin
      assert_raises(SystemExit) { capture_io { Demo::Seed.new.run } }
    ensure
      Rails.env.singleton_class.send(:remove_method, :production?)
    end

    assert_equal before, counts
  end

  test "ensure_regions는 경상남도와 고성군을 한 번만 만들고 고성군을 돌려준다" do
    clear_regions

    assert_difference -> { Region.count }, 2 do
      goseong = Demo::Seed.new.ensure_regions

      assert_equal "고성군", goseong.name
      assert_equal "경상남도", goseong.parent.name
      assert_equal [ [ 34.8, 128.1 ], [ 35.1, 128.5 ] ], goseong.bounds
    end

    assert_no_difference -> { Region.count } do
      Demo::Seed.new.ensure_regions
    end
  end

  test "ensure_regions는 이미 있는 고성군을 고치지 않고 그대로 쓴다" do
    goseong = regions(:goseong)
    goseong.update!(south: 34.9, north: 35.0)

    assert_no_difference -> { Region.count } do
      assert_equal goseong, Demo::Seed.new.ensure_regions
    end

    assert_equal [ [ 34.9, 128.1 ], [ 35.0, 128.5 ] ], goseong.reload.bounds
  end

  test "provision_stops는 모든 데모 정류장에 지역을 지정하고 다시 실행해도 중복으로 만들지 않는다" do
    TraccarGeofenceSync.stub_credentials(base_url: "http://traccar.test", email: "admin@test.com", password: "secret")
    stub_request(:post, "http://traccar.test/api/geofences")
      .to_return(Demo::Seed::STOPS.size.times.map { |i| { status: 200, body: { id: 770 + i }.to_json, headers: { "Content-Type" => "application/json" } } })
    StopVisit.delete_all
    RouteStop.delete_all
    Stop.delete_all
    seed = Demo::Seed.new
    goseong = seed.ensure_regions

    assert_difference -> { Stop.count }, Demo::Seed::STOPS.size do
      capture_io { seed.provision_stops(goseong) }
    end
    assert_equal [ goseong.id ], Stop.where(name: Demo::Seed::STOPS.keys).pluck(:region_id).uniq

    assert_no_difference -> { Stop.count } do
      capture_io { seed.provision_stops(goseong) }
    end
  end

  private

  # 픽스처에 이미 있는 데모 지역 코드를 지워 처음부터 만드는 상황을 만든다.
  def clear_regions
    Stop.update_all(region_id: nil)
    Region.delete_all
  end

  def counts
    [ User.count, Stop.count, Route.count, Bus.count ]
  end
end
