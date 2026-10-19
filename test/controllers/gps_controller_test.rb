require "test_helper"

class GpsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bus = buses(:one)
    @bus.update!(traccar_unique_id: "gps-test-device")
  end

  test "POST /gps는 유효한 OsmAnd 페이로드를 수신해 CurrentPosition/PositionHistory를 생성한다" do
    assert_difference -> { CurrentPosition.count } => 1,
                      -> { PositionHistory.count } => 1 do
      post gps_path, params: {
        id: @bus.traccar_unique_id,
        lat: 34.123456,
        lon: 128.123456,
        speed: 10.5,
        bearing: 90.0,
        battery: 80,
        accuracy: 5.0,
        timestamp: "2026-10-18T12:00:00Z"
      }
    end

    assert_response :ok
  end

  test "GET /gps도 지원한다" do
    assert_difference -> { CurrentPosition.count } => 1 do
      get gps_path, params: {
        id: @bus.traccar_unique_id,
        lat: 34.123456,
        lon: 128.123456,
        timestamp: "2026-10-18T12:00:00Z"
      }
    end

    assert_response :ok
  end

  test "알 수 없는 단말은 200 ack로 무시한다" do
    post gps_path, params: { id: "unknown-device", lat: 34.0, lon: 128.0 }

    assert_response :ok
  end

  test "누락된 좌표는 200 ack로 무시한다" do
    post gps_path, params: { id: @bus.traccar_unique_id, lat: nil, lon: nil }

    assert_response :ok
  end

  test "숫자 타임스탬프는 501 Not Implemented를 반환한다" do
    post gps_path, params: { id: @bus.traccar_unique_id, lat: 34.0, lon: 128.0, timestamp: 1729252800 }

    assert_response :not_implemented
  end

  test "Device 스키마는 조회하지만 P0에서 인증은 하지 않는다" do
    Device.create!(bus: @bus, unique_id: "gps-test-device")

    assert_difference -> { CurrentPosition.count } => 1 do
      post gps_path, params: {
        id: "gps-test-device",
        lat: 34.0,
        lon: 128.0,
        timestamp: "2026-10-18T12:00:00Z"
      }
    end

    assert_response :ok
  end
end
