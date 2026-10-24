require "test_helper"
require "rake"

class TraccarRakeTest < ActiveSupport::TestCase
  BASE_URL = "http://traccar.rake.test".freeze

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("traccar:sync")
    @original_config = Rails.configuration.x.traccar
    Rails.configuration.x.traccar = ActiveSupport::OrderedOptions.new.merge!(api_base_url: BASE_URL, api_email: "a@test.com", api_password: "pw")

    # 생성 응답은 id가 필요하고, 수정·연결 응답은 본문을 보지 않으므로 하나의 응답으로 충분하다.
    @next_id = 100
    stub_request(:any, /#{Regexp.escape(BASE_URL)}/).to_return { { status: 200, body: { id: @next_id += 1 }.to_json, headers: { "Content-Type" => "application/json" } } }

    Route.update_all(traccar_group_id: nil)
    Stop.update_all(traccar_geofence_id: nil)
    Bus.update_all(traccar_device_id: nil)
    RouteBus.create!(route: routes(:one), bus: buses(:one))
  end

  teardown do
    Rails.configuration.x.traccar = @original_config
  end

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    capture_io { task.invoke }
  end

  test "sync는 group, geofence, device를 만들고 배차를 연결한다" do
    out, = run_task("traccar:sync")

    assert_match "완료.", out
    assert routes(:one).reload.traccar_group_id.present?
    assert Stop.where(route: routes(:one)).select(&:coordinates?).all? { |stop| stop.reload.traccar_geofence_id.present? }
    assert Bus.all.all? { |bus| bus.reload.traccar_device_id.present? }
    assert_requested :post, "#{BASE_URL}/api/permissions", at_least_times: 1
  end

  test "sync를 다시 실행하면 새로 만들지 않고 기존 id로 수정한다" do
    run_task("traccar:sync")
    group_id = routes(:one).reload.traccar_group_id
    device_id = buses(:one).reload.traccar_device_id

    run_task("traccar:sync")

    assert_equal group_id, routes(:one).reload.traccar_group_id
    assert_equal device_id, buses(:one).reload.traccar_device_id
    assert_requested :put, "#{BASE_URL}/api/groups/#{group_id}"
  end

  test "sync는 실패한 항목을 보고하고 비정상 종료한다" do
    stub_request(:post, "#{BASE_URL}/api/devices").to_return(status: 400, body: "")

    error = assert_raises(SystemExit) { run_task("traccar:sync") }

    assert_not error.success?
    assert Bus.all.none? { |bus| bus.reload.traccar_device_id }
    assert routes(:one).reload.traccar_group_id.present?
  end

  test "sync는 접속 정보가 없으면 실행하지 않는다" do
    Rails.configuration.x.traccar = ActiveSupport::OrderedOptions.new

    assert_raises(SystemExit) { run_task("traccar:sync") }
    assert_not_requested :any, /#{Regexp.escape(BASE_URL)}/
  end

  test "reset_ids는 저장된 traccar id를 모두 비운다" do
    run_task("traccar:sync")

    run_task("traccar:reset_ids")

    assert Route.all.all? { |route| route.traccar_group_id.nil? }
    assert Stop.all.all? { |stop| stop.traccar_geofence_id.nil? }
    assert Bus.all.all? { |bus| bus.traccar_device_id.nil? }
  end
end
