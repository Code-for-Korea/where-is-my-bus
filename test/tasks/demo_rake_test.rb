require "test_helper"
require "rake"

class DemoRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("demo:drive")
    @original = ENV["DEMO_DEVICE_ID"]
  end

  teardown do
    ENV["DEMO_DEVICE_ID"] = @original
  end

  def drive(bus_arg)
    captured = nil
    fake = Struct.new(:run).new(nil)
    task = Rake::Task["demo:drive"]
    task.reenable
    Demo::BusSimulator.define_singleton_method(:new) { |**options| captured = options; fake }
    begin
      capture_io { task.invoke(bus_arg, "1") }
    ensure
      Demo::BusSimulator.singleton_class.remove_method(:new)
    end
    captured
  end

  test "DEMO_DEVICE_ID가 있으면 Bus를 찾지 않고 그 값을 deviceId로 쓴다" do
    ENV["DEMO_DEVICE_ID"] = "remote-device"

    assert_equal "remote-device", drive("로컬에 없는 번호판")[:device_id]
  end

  test "DEMO_DEVICE_ID가 없으면 로컬 DB의 버스에서 deviceId를 가져온다" do
    ENV.delete("DEMO_DEVICE_ID")
    bus = buses(:one)

    assert_equal bus.traccar_unique_id, drive(bus.license_plate)[:device_id]
  end
end
