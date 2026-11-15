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

  test "wrapper reacts to region changes" do
    get new_admin_stop_path

    assert_select "[data-controller=stop-map][data-action~='region-select:changed@window->stop-map#fitRegion']"
  end

  test "new form without any stop passes empty region bounds" do
    Stop.update_all(region_id: nil)

    get new_admin_stop_path

    assert_select "[data-controller=stop-map][data-stop-map-region-bounds-value=?]", "[]"
  end

  test "new form passes the bounds of the last registered region" do
    regions(:ulleung).update!(south: 37.4, west: 130.8, north: 37.6, east: 131.0)
    Stop.create!(name: "울릉 정류장", lat: 37.5, lng: 130.9, region: regions(:ulleung))

    get new_admin_stop_path

    assert_select "[data-controller=stop-map][data-stop-map-region-bounds-value=?]", regions(:ulleung).bounds.to_json
  end

  test "country bounds are empty when no root region has bounds" do
    get new_admin_stop_path

    assert_select "[data-controller=stop-map][data-stop-map-country-bounds-value=?]", "[]"
  end

  test "country bounds cover the root regions" do
    regions(:gyeongnam).update!(south: 34.5, west: 127.5, north: 35.5, east: 129.0)

    get new_admin_stop_path

    assert_select "[data-controller=stop-map][data-stop-map-country-bounds-value=?]", Region.country_bounds.to_json
    assert_equal [ [ 34.5, 127.5 ], [ 35.5, 129.0 ] ], Region.country_bounds
  end

  test "edit form passes the stop's region bounds" do
    get edit_admin_stop_path(stops(:hospital))

    assert_select "[data-controller=stop-map][data-stop-map-region-bounds-value=?]", regions(:goseong).bounds.to_json
  end

  test "region without own bounds falls back to its ancestor's" do
    stop = stops(:hospital)
    stop.update_columns(region_id: regions(:ulleung_eup).id)

    get edit_admin_stop_path(stop)

    assert_select "[data-controller=stop-map][data-stop-map-region-bounds-value=?]", regions(:ulleung).bounds.to_json
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

  test "show page renders a read-only map at the stop's coordinates" do
    stop = stops(:terminal)

    get admin_stop_path(stop)

    assert_select "[data-controller=stop-view-map][data-stop-view-map-lat-value=?][data-stop-view-map-lng-value=?]",
                  stop.lat.to_f.to_s, stop.lng.to_f.to_s do
      assert_select "[data-stop-view-map-target=canvas]"
    end
  end

  test "region link comes right after the dashboard in the navigation" do
    get admin_root_path

    labels = css_select("nav a").map { |a| a.text.strip }
    assert_equal [ "대시보드", "지역" ], labels.first(2)
  end
end
