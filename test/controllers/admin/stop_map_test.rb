require "test_helper"

# 정류장 폼의 좌표 선택 지도(Leaflet)에 필요한 마크업. 지도 동작 자체는 브라우저에서 확인한다.
class Admin::StopMapTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:operator)) }

  test "new form wires the map to the coordinate inputs" do
    get new_admin_stop_path

    assert_select "[data-controller=stop-map]" do
      assert_select "input[name='stop[lat]'][data-stop-map-target=lat][data-action~='input->stop-map#syncFromInputs']"
      assert_select "input[name='stop[lng]'][data-stop-map-target=lng][data-action~='input->stop-map#syncFromInputs']"
      assert_select "[data-stop-map-target=canvas]"
    end
  end

  test "form passes the center of existing stops to the map" do
    get new_admin_stop_path

    assert_select "[data-controller=stop-map][data-stop-map-center-value=?]", Stop.center.to_json
  end

  test "form passes an empty center when no stops exist" do
    StopVisit.delete_all
    RouteStop.delete_all
    Stop.delete_all

    get new_admin_stop_path

    assert_select "[data-controller=stop-map][data-stop-map-center-value=?]", "[]"
  end

  test "form always passes the fallback center" do
    get new_admin_stop_path

    assert_select "[data-controller=stop-map][data-stop-map-fallback-value=?]", Stop::MAP_FALLBACK_CENTER.to_json
  end

  test "edit form keeps the stored coordinates in the inputs" do
    stop = stops(:hospital)

    get edit_admin_stop_path(stop)

    assert_select "input[data-stop-map-target=lat][value=?]", stop.lat.to_s
    assert_select "input[data-stop-map-target=lng][value=?]", stop.lng.to_s
  end

  test "form loads the Leaflet stylesheet" do
    get new_admin_stop_path

    assert_select "head link[rel=stylesheet][href*='leaflet']"
  end
end
