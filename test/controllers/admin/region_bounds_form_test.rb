require "test_helper"

# 지역 폼의 bbox 지도(Leaflet)에 필요한 마크업. 지도 동작 자체는 브라우저에서 확인한다.
class Admin::RegionBoundsFormTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:operator)) }

  test "new form wires the bounds map to the four inputs" do
    get new_admin_region_path

    assert_select "[data-controller~=region-bounds]" do
      %w[south west north east].each do |attr|
        assert_select "input[name='region[#{attr}]'][data-region-bounds-target=#{attr}][data-action~='input->region-bounds#syncFromInputs']"
      end
      assert_select "[data-region-bounds-target=canvas]"
      assert_select "[data-region-bounds-target=status]"
      assert_select "button[type=button][data-action~='click->region-bounds#useCurrentView']"
      assert_select "button[type=button][data-action~='click->region-bounds#clear']"
    end
    assert_equal [], initial_bounds
    assert_select "head link[rel=stylesheet][href*='leaflet']"
  end

  test "edit form of a region with its own bbox passes it as the initial bounds" do
    get edit_admin_region_path(regions(:goseong))

    assert_equal [ [ 34.8, 128.1 ], [ 35.1, 128.5 ] ], initial_bounds
    assert_select "input[name='region[south]'][value='34.8']"
    assert_select "input[name='region[east]'][value='128.5']"
  end

  test "edit form of a region without its own bbox uses the parent bounds as fallback" do
    get edit_admin_region_path(regions(:ulleung_eup))

    assert_equal [], initial_bounds
    assert_equal regions(:ulleung).bounds, fallback_bounds
  end

  test "new form with a parent falls back to the parent bounds" do
    get new_admin_region_path(parent_id: regions(:ulleung).id)

    assert_equal [], initial_bounds
    assert_equal regions(:ulleung).bounds, fallback_bounds
  end

  test "new form without a parent falls back to the country bounds" do
    get new_admin_region_path
    assert_equal [], fallback_bounds

    regions(:gyeongbuk).update!(south: 33, west: 125, north: 39, east: 130)
    get new_admin_region_path
    assert_equal Region.country_bounds, fallback_bounds
  end

  private

  def initial_bounds = JSON.parse(css_select("[data-controller~=region-bounds]").first["data-region-bounds-initial-bounds-value"])

  def fallback_bounds = JSON.parse(css_select("[data-controller~=region-bounds]").first["data-region-bounds-fallback-bounds-value"])
end
