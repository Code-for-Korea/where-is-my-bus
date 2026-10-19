require "test_helper"

class Admin::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Setting.delete_all
  end

  test "운영자가 설정 화면을 열면 라디오와 현재 API 키가 표시된다" do
    Setting.store!(:map_provider, "google")
    Setting.store!(:google_maps_api_key, "AIza-current")

    sign_in_as(users(:operator))
    get edit_admin_setting_path

    assert_response :ok
    assert_select "input[type='radio'][value='google'][checked='checked']"
    assert_select "input[type='radio'][value='kakao']"
    assert_select "input[type='radio'][value='osm']"
    assert_select "input[name='settings[api_key]'][value='AIza-current']"
  end

  test "라디오에서 선택한 제공자와 API 키를 저장한다" do
    sign_in_as(users(:operator))

    patch admin_setting_path, params: { settings: { map_provider: "kakao", api_key: "kakao-js-key" } }

    assert_redirected_to edit_admin_setting_path
    assert_equal "설정을 저장했습니다.", flash[:notice]
    assert_equal "kakao", Setting.fetch(:map_provider)
    assert_equal "kakao-js-key", Setting.fetch(:kakao_maps_app_key)
  end

  test "제공자를 바꿔도 이전 제공자의 저장된 키는 유지된다" do
    Setting.store!(:map_provider, "google")
    Setting.store!(:google_maps_api_key, "AIza-keep")

    sign_in_as(users(:operator))
    patch admin_setting_path, params: { settings: { map_provider: "kakao", api_key: "kakao-js-key" } }

    assert_equal "kakao-js-key", Setting.fetch(:kakao_maps_app_key)
    assert_equal "AIza-keep", Setting.fetch(:google_maps_api_key)
  end

  test "osm 선택 시 API 키는 저장하지 않는다" do
    Setting.store!(:map_provider, "google")
    Setting.store!(:google_maps_api_key, "AIza-keep")

    sign_in_as(users(:operator))
    patch admin_setting_path, params: { settings: { map_provider: "osm", api_key: "ignored" } }

    assert_equal "osm", Setting.fetch(:map_provider)
    assert_equal "AIza-keep", Setting.fetch(:google_maps_api_key)
    assert_nil Setting.fetch(:kakao_maps_app_key)
  end

  test "빈 키로 저장하면 키가 해제된다" do
    Setting.store!(:map_provider, "google")
    Setting.store!(:google_maps_api_key, "AIza-old")

    sign_in_as(users(:operator))
    patch admin_setting_path, params: { settings: { map_provider: "google", api_key: "" } }

    assert_nil Setting.fetch(:google_maps_api_key)
  end

  test "저장한 지도 설정이 노선 지도 화면에 반영된다" do
    Setting.store!(:map_provider, "kakao")
    Setting.store!(:kakao_maps_app_key, "kakao-view-key")

    get route_map_path(id: routes(:one).id)

    assert_response :ok
    assert_select "[data-map-provider-value='kakao']"
    assert_includes response.body, "dapi.kakao.com/v2/maps/sdk.js?appkey=kakao-view-key"
  end

  test "설정이 없으면 지도 화면은 google 기본값이고 안내 메시지를 표시한다" do
    get route_map_path(id: routes(:one).id)

    assert_response :ok
    assert_select "[data-map-provider-value='google']"
    assert_includes response.body, "Google Maps API 키가 설정되지 않았습니다"
  end

  test "member는 설정 화면에 접근할 수 없다" do
    sign_in_as(users(:member))

    get edit_admin_setting_path

    assert_redirected_to root_path
    assert_equal "운영자만 접근할 수 있습니다.", flash[:alert]
  end
end
