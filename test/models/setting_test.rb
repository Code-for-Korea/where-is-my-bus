require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "store!로 저장한 값을 fetch로 읽는다" do
    assert_nil Setting.fetch(:google_maps_api_key)

    Setting.store!(:google_maps_api_key, "AIza-test")

    assert_equal "AIza-test", Setting.fetch(:google_maps_api_key)
  end

  test "store!는 같은 키를 덮어쓴다" do
    Setting.store!(:google_maps_api_key, "first")
    Setting.store!(:google_maps_api_key, "second")

    assert_equal "second", Setting.fetch(:google_maps_api_key)
    assert_equal 1, Setting.count
  end

  test "fetch는 빈 값을 nil로 반환한다" do
    Setting.store!(:google_maps_api_key, "")
    assert_nil Setting.fetch(:google_maps_api_key)

    Setting.store!(:google_maps_api_key, "   ")
    assert_nil Setting.fetch(:google_maps_api_key)
  end

  test "같은 키가 중복 저장되지 않는다" do
    Setting.store!(:a, "1")

    assert_raises(ActiveRecord::RecordInvalid) do
      Setting.create!(key: "a", value: "2")
    end
  end
end
