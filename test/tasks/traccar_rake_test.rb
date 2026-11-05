require "test_helper"
require "rake"

class TraccarRakeTest < ActiveSupport::TestCase
  SERVICES = [ TraccarGroupSync, TraccarGeofenceSync, TraccarDeviceSync, TraccarRouteStopLink ].freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("traccar:sync")
    stub_traccar_credentials(*SERVICES)

    # 생성 응답은 id가 필요하고, 수정·연결 응답은 본문을 보지 않으므로 하나의 응답으로 충분하다.
    @next_id = 500
    stub_request(:any, /#{Regexp.escape(TRACCAR_API)}/).to_return do
      { status: 200, body: { id: @next_id += 1 }.to_json, headers: { "Content-Type" => "application/json" } }
    end

    Route.update_all(traccar_group_id: nil)
    Stop.update_all(traccar_geofence_id: nil)
    Bus.update_all(traccar_device_id: nil)
  end

  teardown do
    SERVICES.each { |service| service.stub_credentials(base_url: nil, email: nil, password: nil) }
  end

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    capture_io { task.invoke }
  end

  test "sync는 group, geofence, device를 만들고 정류장을 노선에 연결한다" do
    out, = run_task("traccar:sync")

    assert_match "완료.", out
    assert Route.all.all? { |route| route.reload.traccar_group_id.present? }
    assert Stop.all.all? { |stop| stop.reload.traccar_geofence_id.present? }
    assert Bus.all.all? { |bus| bus.reload.traccar_device_id.present? }
    assert_requested :post, "#{TRACCAR_API}/api/permissions", times: RouteStop.count
  end

  test "sync를 다시 실행하면 새로 만들지 않고 기존 id로 수정한다" do
    run_task("traccar:sync")
    group_id = routes(:one).reload.traccar_group_id
    device_id = buses(:one).reload.traccar_device_id

    run_task("traccar:sync")

    assert_equal group_id, routes(:one).reload.traccar_group_id
    assert_equal device_id, buses(:one).reload.traccar_device_id
    assert_requested :put, "#{TRACCAR_API}/api/groups/#{group_id}"
  end

  test "sync는 실패한 항목을 보고하고 비정상 종료한다" do
    stub_request(:post, "#{TRACCAR_API}/api/devices").to_return(status: 400, body: "")

    error = assert_raises(SystemExit) { run_task("traccar:sync") }

    assert_not error.success?
    assert Bus.all.none? { |bus| bus.reload.traccar_device_id }
    assert routes(:one).reload.traccar_group_id.present?
  end

  test "sync는 환경변수를 채워도 끝난 뒤 원래대로 되돌린다" do
    original = ENV.values_at("TRACCAR_API_BASE_URL", "TRACCAR_API_TOKEN")

    run_task("traccar:sync")

    assert_equal original, ENV.values_at("TRACCAR_API_BASE_URL", "TRACCAR_API_TOKEN")
  end

  test "reset_ids는 저장된 traccar id를 모두 비운다" do
    run_task("traccar:sync")

    run_task("traccar:reset_ids")

    assert Route.all.all? { |route| route.traccar_group_id.nil? }
    assert Stop.all.all? { |stop| stop.traccar_geofence_id.nil? }
    assert Bus.all.all? { |bus| bus.traccar_device_id.nil? }
  end
end
