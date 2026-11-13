require "test_helper"

# 정류장 폼의 지역 연쇄 선택 마크업. 선택 동작(JS)은 브라우저에서 확인한다.
class Admin::StopRegionFormTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:operator)) }

  test "new form renders a select for every level, only the top level enabled, and no error" do
    Stop.update_all(region_id: nil)
    get new_admin_stop_path

    assert_select "[data-controller~=region-select]" do
      assert_select "[data-region-select-url-value=?]", children_admin_regions_path
      assert_select "input[type=hidden][name='stop[region_id]'][data-region-select-target=input]"
      assert_select "[data-region-select-target=container] select", count: 4
      %w[시도 시군구 읍면동 리].each_with_index do |label, index|
        assert_select "select[aria-label=?][data-level=?]", label, (index + 1).to_s
        assert_select "label[for=region_select_level_#{index + 1}]", text: label
      end
      assert_select "select[aria-label=시도]:not([disabled]) option:not([value=''])", count: 4
      %w[경상남도 경상북도 경기도 세종특별자치시].each { |name| assert_select "option", text: name }
      assert_select "option", text: /폐지시/, count: 0
      %w[시군구 읍면동 리].each { |label| assert_select "select[aria-label=?][disabled]", label }
    end
    assert_select "[data-controller~=stop-map] [data-controller~=region-select]", count: 0
  end

  test "new form is prefilled with the region of the last registered stop" do
    get new_admin_stop_path

    assert_select "input[name='stop[region_id]'][value=?]", regions(:goseong).id.to_s
    assert_select "select[aria-label=시도] option[selected]", text: "경상남도"
    assert_select "select[aria-label=시군구] option[selected]", text: "고성군"
  end

  test "edit form shows the chain of the current region" do
    get edit_admin_stop_path(stops(:hospital))

    assert_select "input[name='stop[region_id]'][value=?]", regions(:goseong).id.to_s
    assert_select "[data-region-select-target=container] select", count: 4
    assert_select "select[aria-label=시도] option[selected]", text: "경상남도"
    assert_select "select[aria-label=시군구] option[selected]", text: "고성군"
    assert_select "select[aria-label=읍면동][disabled]"
  end

  test "edit form for a level 3 region selects three levels" do
    stop = stops(:hospital)
    stop.update_columns(region_id: regions(:ulleung_eup).id)
    get edit_admin_stop_path(stop)

    assert_select "select[aria-label=시도] option[selected]", text: "경상북도"
    assert_select "select[aria-label=시군구] option[selected]", text: "울릉군"
    assert_select "select[aria-label=읍면동] option[selected]", text: "울릉읍"
    assert_select "select[aria-label=리][disabled]"
  end

  test "a region with active children gets its next level enabled and unselected" do
    stops(:hospital).update_columns(region_id: regions(:ulleung).id)
    get edit_admin_stop_path(stops(:hospital))

    assert_select "select[aria-label=읍면동]:not([disabled])" do
      assert_select "option[selected]", count: 0
      assert_select "option", text: "울릉읍"
    end
  end

  test "a level-skipping region fills the level it actually has" do
    stops(:hospital).update_columns(region_id: regions(:sejong).id)
    get edit_admin_stop_path(stops(:hospital))

    assert_select "select[aria-label=시군구][disabled]"
    assert_select "select[aria-label=읍면동]:not([disabled]) option", text: "반곡동"
  end

  test "an inactive chain region stays selectable but others are not offered" do
    regions(:goseong).update_columns(active: false)
    get edit_admin_stop_path(stops(:hospital))

    assert_select "option[selected]", text: "고성군 (비활성)"

    get new_admin_stop_path
    assert_select "option", text: /폐지시/, count: 0
  end

  test "region comes before the stop name in the form" do
    get new_admin_stop_path

    html = response.body
    assert_operator html.index("region_select_level_1"), :<, html.index("stop_name")
  end

  test "region selects keep room for the arrow" do
    get new_admin_stop_path

    assert_select "[data-region-select-target=container] select.select-chevron", count: 4
  end

  test "failed create with only a province asks for a city or county" do
    post admin_stops_path, params: { stop: { name: "새 정류장", lat: "35", lng: "128", region_id: regions(:gyeongnam).id } }

    assert_response :unprocessable_entity
    assert_select "select[aria-label=시도] option[selected]", text: "경상남도"
    assert_select "div.bg-red-50 li", text: "지역: 시군구까지 선택해 주세요", count: 1
    assert_select "[data-role=region-error]", count: 0
  end

  test "failed create without a region asks for one" do
    post admin_stops_path, params: { stop: { name: "새 정류장", lat: "35", lng: "128", region_id: "" } }

    assert_response :unprocessable_entity
    assert_select "div.bg-red-50 li", text: /지역/, count: 1
    assert_select "[data-role=region-error]", count: 0
  end

  test "options carry level, bounds and has-children data" do
    stops(:hospital).update_columns(region_id: regions(:gyeonggi).id)
    get edit_admin_stop_path(stops(:hospital))

    assert_select "option[value=?][data-level=1][data-has-children=true][data-bounds='']", regions(:gyeonggi).id.to_s
    assert_select "option[value=?][data-level=2][data-has-children=false][data-bounds='']", regions(:suwon).id.to_s
    assert_select "option[value=?][data-has-children=true]", regions(:suwon_jangan).id.to_s

    stops(:hospital).update_columns(region_id: regions(:goseong).id)
    get edit_admin_stop_path(stops(:hospital))

    option = css_select("option[value='#{regions(:goseong).id}']").first
    assert_equal "2", option["data-level"]
    assert_equal "false", option["data-has-children"]
    assert_equal [ [ 34.8, 128.1 ], [ 35.1, 128.5 ] ], JSON.parse(option["data-bounds"])
  end

  test "index and show display the region full name" do
    get admin_stops_path
    assert_select "th", text: "지역"
    assert_select "td", text: "경상남도 고성군", minimum: 1

    get admin_stop_path(stops(:hospital))
    assert_select "div", text: "경상남도 고성군"
  end

  test "index query count does not grow with the number of stops" do
    # 조상 단계 수만큼의 미리 읽기는 고정 비용이므로 가장 깊은 지역을 먼저 하나 둔다.
    Stop.create!(name: "기준", lat: 35.0, lng: 128.0, region: regions(:ulleung_eup))
    before = count_queries { get admin_stops_path }

    10.times do |i|
      Stop.create!(name: "추가 #{i}", lat: 35.0, lng: 128.0, region: regions(:ulleung_eup))
    end

    assert_equal before, count_queries { get admin_stops_path }
  end

  private

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
