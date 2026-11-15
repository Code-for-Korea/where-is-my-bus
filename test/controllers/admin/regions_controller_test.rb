require "test_helper"

class Admin::RegionsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:operator)) }

  test "index redirects unauthenticated requests to login" do
    delete session_path
    get admin_regions_path

    assert_redirected_to new_session_path
  end

  test "index rejects non-operator members" do
    delete session_path
    User.create!(email_address: "member@example.com", password: "password123", role: :member)
    sign_in_as(User.find_by!(email_address: "member@example.com"))

    get admin_regions_path

    assert_redirected_to root_path
    assert_equal "운영자만 접근할 수 있습니다.", flash[:alert]
  end

  test "index without params lists all regions in one table ordered by level" do
    get admin_regions_path

    assert_response :ok
    assert_select "td", text: /경상남도 고성군/
    assert_select "td", text: /경기도 수원시 장안구 파장동/
    levels = css_select("tbody tr td[data-column=level]").map { |td| td.text.to_i }
    assert_equal Region.count, levels.size
    assert_equal levels.sort, levels
  end

  test "region_id lists that region and everything below it" do
    get admin_regions_path(region_id: regions(:gyeonggi).id)

    assert_response :ok
    assert_select "td", text: /경기도 수원시 장안구 파장동/
    assert_select "td", text: /경기도 수원시 장안구$/
    assert_select "td", text: /^경기도$/
    assert_select "td", text: /경상남도/, count: 0
  end

  test "an unknown region_id is ignored" do
    get admin_regions_path(region_id: 0)

    assert_response :ok
    assert_select "td", text: /경상남도 고성군/
  end

  test "with_stops lists only regions that have stops" do
    get admin_regions_path(with_stops: "1")

    assert_response :ok
    assert_select "tbody tr", count: Region.where(id: Stop.select(:region_id)).count
    assert_select "td", text: /경상남도 고성군/
    assert_select "td", text: /울릉/, count: 0
    assert_select "input[type=checkbox][name=with_stops][checked]"
  end

  test "region_id and with_stops combine" do
    get admin_regions_path(region_id: regions(:gyeongbuk).id, with_stops: "1")

    assert_select "td", text: /조건에 맞는 지역이 없습니다\./
  end

  test "status filter lists only active or only inactive regions" do
    get admin_regions_path(status: "inactive")

    assert_select "tbody tr", count: Region.where(active: false).count
    assert_select "td", text: /폐지시/
    assert_select "td[data-column=status]", text: "활성", count: 0

    get admin_regions_path(status: "active")

    assert_select "tbody tr", count: Region.where(active: true).count
    assert_select "td", text: /폐지시/, count: 0
    assert_select "td[data-column=status]", text: "비활성", count: 0
  end

  test "an unknown status is ignored" do
    get admin_regions_path(status: "weird")

    assert_response :ok
    assert_select "tbody tr", count: Region.count
    assert_select "input[name=status][value=''][checked]"
  end

  test "status filter combines with the other filters" do
    get admin_regions_path(status: "inactive", with_stops: "1")

    assert_select "td", text: /조건에 맞는 지역이 없습니다\./

    get admin_regions_path(status: "inactive", region_id: regions(:gyeonggi).id)

    assert_select "tbody tr", count: 1
    assert_select "td", text: /폐지시/
  end

  test "status filter is a three-way control with the current choice checked" do
    get admin_regions_path(status: "inactive")

    assert_select "fieldset[data-role=status-filter]" do
      assert_select "input[type=radio][name=status]", count: 3
      assert_select "input[name=status][value=inactive][checked]"
      assert_select "input[name=status][value=active][checked]", count: 0
    end
    get admin_regions_path
    assert_select "fieldset[data-role=status-filter] input[name=status][value=''][checked]"
  end

  test "filters are grouped into location and condition areas" do
    get admin_regions_path

    assert_select "[data-role=location-filter] select", count: 4
    assert_select "[data-role=condition-filter]" do
      assert_select "input[name=q]"
      assert_select "fieldset[data-role=status-filter]"
      assert_select "input[type=checkbox][name=with_stops]"
    end
    assert_select "form [data-role=active-filters]", count: 0
    assert_select "a[href=?]", new_admin_region_path, text: /지역 추가/
    assert_select "form a", text: /지역 추가/, count: 0
  end

  test "applied filters appear as chips that each remove only their own filter" do
    get admin_regions_path(region_id: regions(:gyeonggi).id, q: "수원", status: "active", with_stops: "1")

    assert_select "[data-role=active-filters]" do
      assert_select "a", text: /지역: 경기도/
      assert_select "a", text: /이름: 수원/
      assert_select "a", text: /상태: 활성/
      assert_select "a", text: /정류장이 있는 지역/
      assert_select "a[href=?]", admin_regions_path(q: "수원", status: "active", with_stops: 1), text: /지역: 경기도/
      assert_select "a[href=?]", admin_regions_path(region_id: regions(:gyeonggi).id, status: "active", with_stops: 1), text: /이름: 수원/
      assert_select "a[href=?]", admin_regions_path, text: "필터 모두 해제"
    end
  end

  test "pagination keeps the status filter" do
    120.times { |i| Region.create!(code: "8#{i.to_s.rjust(9, '0')}", name: "비활성#{i}", level: 1, kind: "시도", active: false) }

    get admin_regions_path(status: "inactive")

    assert_select "nav[aria-label=페이지] a[rel=next][href=?]", admin_regions_path(status: "inactive", page: 2)
  end

  test "search shows matches with full names" do
    get admin_regions_path(q: "울릉")

    assert_response :ok
    assert_select "td", text: /경상북도 울릉군 울릉읍/
    assert_select "td", text: /경상북도 울릉군/
    assert_select "td", text: /고성군/, count: 0
  end

  test "search combines with the region filter" do
    get admin_regions_path(q: "울릉", region_id: regions(:gyeonggi).id)

    assert_select "td", text: /울릉읍/, count: 0
    assert_select "td", text: /조건에 맞는 지역이 없습니다\./
  end

  test "search treats LIKE wildcards literally" do
    get admin_regions_path(q: "%")

    assert_response :ok
    assert_select "td", text: /조건에 맞는 지역이 없습니다\./
  end

  test "search with no match says so" do
    get admin_regions_path(q: "없는지역")

    assert_select "td", text: /조건에 맞는 지역이 없습니다\./
  end

  test "results are paginated, ordered by level, and keep the filters in the links" do
    120.times do |i|
      Region.create!(code: "9#{i.to_s.rjust(9, '0')}", name: "대량지역#{i}", level: 1, kind: "시도")
    end
    total = Region.where("name LIKE ?", "대량지역%").count

    get admin_regions_path(q: "대량지역")
    assert_select "tbody tr", count: 50
    assert_select "nav[aria-label=페이지] a[rel=next][href=?]", admin_regions_path(q: "대량지역", page: 2)
    assert_select "nav[aria-label=페이지] a[rel=prev]", count: 0
    assert_select "p", text: /총 #{total}개 · 1 \/ 3 페이지/

    get admin_regions_path(q: "대량지역", page: 3)
    assert_select "tbody tr", count: total - 100
    assert_select "nav[aria-label=페이지] a[rel=prev][href=?]", admin_regions_path(q: "대량지역", page: 2)
    assert_select "nav[aria-label=페이지] a[rel=next]", count: 0

    get admin_regions_path(q: "대량지역", page: 99)
    assert_select "p", text: /3 \/ 3 페이지/
  end

  test "no pagination links when everything fits on one page" do
    get admin_regions_path

    assert_select "nav[aria-label=페이지]", count: 0
  end

  test "inactive regions are listed with a badge" do
    get admin_regions_path(region_id: regions(:gyeonggi).id)

    assert_select "tr", text: /폐지시/ do
      assert_select "span", text: "비활성"
    end
    assert_select "tr", text: /수원시 장안구\s+4111100000/ do
      assert_select "span", text: "비활성", count: 0
    end
  end

  test "rows show the stop count and link to the detail page" do
    get admin_regions_path(region_id: regions(:gyeongnam).id)

    assert_select "tr", text: /경상남도 고성군/ do
      assert_select "td[data-column=stops]", text: Stop.where(region: regions(:goseong)).count.to_s
      assert_select "a[href=?]", admin_region_path(regions(:goseong)), text: "경상남도 고성군"
      assert_select "[data-controller=row-link][data-row-link-url-value=?]", admin_region_path(regions(:goseong))
    end
  end

  test "list does not carry bounds, child counts or edit and delete buttons" do
    get admin_regions_path(region_id: regions(:gyeongbuk).id)

    %w[남 서 북 동 하위\ 지역].each { |label| assert_select "thead th", text: label, count: 0 }
    assert_select "td[data-column=children]", count: 0
    assert_select "a", text: "수정", count: 0
    assert_select "button", text: "삭제", count: 0
  end

  test "status column shows active and inactive for every row" do
    get admin_regions_path(region_id: regions(:gyeonggi).id)

    assert_select "tr", text: /폐지시/ do
      assert_select "td[data-column=status]", text: "비활성"
    end
    assert_select "tr", text: /수원시 장안구\s+4111100000/ do
      assert_select "td[data-column=status]", text: "활성"
    end
    assert_select "td[data-column=status]:empty", count: 0
  end

  test "table columns follow the region CSV" do
    get admin_regions_path(region_id: regions(:gyeongbuk).id)

    headers = css_select("thead th").map { |th| th.text.strip }
    assert_equal %w[지역 코드 상위\ 코드 레벨 종류 정류장 상태], headers
    assert_select "tr", text: /울릉읍/ do
      assert_select "td[data-column=code]", text: "4794025000"
      assert_select "td[data-column=parent_code]", text: "4794000000"
      assert_select "td[data-column=level]", text: "3"
      assert_select "td[data-column=kind]", text: "읍면동"
    end
    assert_select "tr", text: /경상북도 울릉군\s+4794000000/ do
      assert_select "td[data-column=parent_code]", text: "4700000000"
    end
    assert_select "tr", text: /^경상북도\s+4700000000/ do
      assert_select "td[data-column=parent_code]", text: "—"
    end
  end

  test "filter form shows a select for every level and marks the chain of the chosen region" do
    get admin_regions_path(region_id: regions(:pajang).id)

    assert_select "form[method=get] input[type=hidden][name=region_id][value=?]", regions(:pajang).id.to_s
    %w[시도 시군구 읍면동 리].each { |label| assert_select "select[aria-label=?]", label }
    assert_select "select[aria-label=시도] option[selected]", text: "경기도"
    assert_select "select[aria-label=시군구] option[selected]", text: "수원시 장안구"
    assert_select "select[aria-label=읍면동] option[selected]", text: "파장동"
    assert_select "select[aria-label=리][disabled]"
  end

  test "filter form without a region has only the top level enabled" do
    get admin_regions_path

    assert_select "select[aria-label=시도]:not([disabled])" do
      assert_select "option", text: "경상남도"
    end
    %w[시군구 읍면동 리].each { |label| assert_select "select[aria-label=?][disabled]", label }
  end

  test "filter form leaves the skipped level disabled for a region whose children skip a level" do
    get admin_regions_path(region_id: regions(:sejong).id)

    assert_select "select[aria-label=시군구][disabled]"
    assert_select "select[aria-label=읍면동]:not([disabled])" do
      assert_select "option", text: "반곡동"
    end
  end

  test "query count does not grow with the number of rows" do
    parent = regions(:gyeongnam)
    add_children = lambda do |count, tag|
      count.times do |i|
        child = Region.create!(code: "#{tag}#{i.to_s.rjust(8, '0')}", name: "#{tag}지역#{i}", level: 2, kind: "시군구", parent: parent)
        Stop.create!(name: "#{tag}정류장#{i}", lat: 35, lng: 128, region: child)
      end
    end

    add_children.call(3, "가")
    few = count_queries { get admin_regions_path(region_id: parent.id) }
    add_children.call(10, "나")
    many = count_queries { get admin_regions_path(region_id: parent.id) }
    assert_equal few, many
  end

  test "nav links to regions on admin pages" do
    get admin_root_path

    assert_select "nav a[href=?]", admin_regions_path, text: "지역"
  end

  test "new renders the form with the parent prefilled" do
    get new_admin_region_path(parent_id: regions(:ulleung).id)

    assert_response :ok
    assert_select "form[action=?]", admin_regions_path
    assert_select "input[name='region[parent_code]'][value=?]", regions(:ulleung).code
    assert_select "p", text: /경상북도 울릉군/
  end

  test "new without parent_id has an empty parent code" do
    get new_admin_region_path

    assert_select "input[name='region[parent_code]']:not([value])"
  end

  test "edit shows current values and the code warning" do
    get edit_admin_region_path(regions(:goseong))

    assert_response :ok
    assert_select "input[name='region[name]'][value=?]", "고성군"
    assert_select "input[name='region[code]'][value=?]", "4882000000"
    assert_select "input[name='region[parent_code]'][value=?]", "4800000000"
    assert_select "input[name='region[south]'][value=?]", "34.8"
    assert_select "p", text: /다음 적재 때 새 지역으로 추가됩니다/
  end

  test "create persists a region under the given parent and redirects to its detail page" do
    assert_difference "Region.count", 1 do
      post admin_regions_path, params: { region: { code: "4882025000", name: "고성읍", level: 3, kind: "읍면동",
                                                   parent_code: regions(:goseong).code, south: "", west: "", north: "", east: "" } }
    end

    region = Region.find_by!(code: "4882025000")
    assert_equal regions(:goseong), region.parent
    assert_nil region.south
    assert_redirected_to admin_region_path(region)
    assert_equal "지역이 등록되었습니다.", flash[:notice]
  end

  test "create without parent redirects to the detail page" do
    post admin_regions_path, params: { region: { code: "5000000000", name: "제주", level: 1, kind: "시도" } }

    assert_redirected_to admin_region_path(Region.find_by!(code: "5000000000"))
  end

  test "create persists a four-value bounding box" do
    post admin_regions_path, params: { region: { code: "5000000000", name: "제주", level: 1, kind: "시도",
                                                 south: "33.1", west: "126.1", north: "33.9", east: "126.9" } }

    region = Region.find_by!(code: "5000000000")
    assert_equal [ [ 33.1, 126.1 ], [ 33.9, 126.9 ] ], region.bounds
  end

  test "create failures re-render with 422 and errors" do
    base = { code: "5000000000", name: "제주", level: 3, kind: "읍면동" }
    cases = {
      "missing name" => base.merge(name: ""),
      "duplicate code" => base.merge(code: regions(:goseong).code),
      "unknown parent_code" => base.merge(parent_code: "0000000000"),
      "parent level not lower" => base.merge(level: 2, parent_code: regions(:goseong).code),
      "partial bbox" => base.merge(south: "33.1", west: "126.1")
    }

    cases.each do |label, params|
      assert_no_difference "Region.count", label do
        post admin_regions_path, params: { region: params }
      end
      assert_response :unprocessable_entity, label
      assert_select "div.bg-red-50 li", minimum: 1
    end
  end

  test "update changes name, bounding box and deactivates" do
    region = regions(:ulleung_eup)

    patch admin_region_path(region), params: { region: { name: "울릉읍내", active: "0",
                                                         south: "37.4", west: "130.8", north: "37.5", east: "130.9" } }

    assert_redirected_to admin_region_path(region)
    assert_equal "지역이 수정되었습니다.", flash[:notice]
    region.reload
    assert_equal "울릉읍내", region.name
    assert_not region.active?
    assert_equal [ [ 37.4, 130.8 ], [ 37.5, 130.9 ] ], region.bounds
  end

  test "update changes the parent via parent_code" do
    region = regions(:ulleung_eup)

    patch admin_region_path(region), params: { region: { parent_code: regions(:goseong).code } }

    assert_equal regions(:goseong), region.reload.parent
    assert_redirected_to admin_region_path(region)
  end

  test "update rejects a level not lower than a child's" do
    patch admin_region_path(regions(:ulleung)), params: { region: { level: 3 } }

    assert_response :unprocessable_entity
    assert_equal 2, regions(:ulleung).reload.level
  end

  test "update with an unknown parent_code re-renders edit" do
    patch admin_region_path(regions(:goseong)), params: { region: { parent_code: "0000000000" } }

    assert_response :unprocessable_entity
    assert_equal regions(:gyeongnam), regions(:goseong).reload.parent
  end

  test "destroy deletes a leaf region without stops" do
    assert_difference "Region.count", -1 do
      delete admin_region_path(regions(:bangok))
    end

    assert_redirected_to admin_regions_path(region_id: regions(:sejong).id)
    assert_response :see_other
    assert_equal "지역이 삭제되었습니다.", flash[:notice]
  end

  test "destroy refuses a region with children and hints at deactivating" do
    assert_no_difference "Region.count" do
      delete admin_region_path(regions(:ulleung))
    end

    assert_redirected_to admin_region_path(regions(:ulleung))
    assert_response :see_other
    assert_match "삭제할 수 없습니다", flash[:alert]
    assert_match "폐지된 지역은 삭제하지 않고 비활성으로 바꾸세요.", flash[:alert]
  end

  test "destroy refuses a region with stops" do
    assert_operator Stop.where(region: regions(:goseong)).count, :>, 0

    assert_no_difference "Region.count" do
      delete admin_region_path(regions(:goseong))
    end

    assert_match "삭제할 수 없습니다", flash[:alert]
  end

  test "non-operators cannot use new, create, update or destroy" do
    delete session_path
    User.create!(email_address: "member@example.com", password: "password123", role: :member)
    sign_in_as(User.find_by!(email_address: "member@example.com"))

    get new_admin_region_path
    assert_redirected_to root_path

    assert_no_difference "Region.count" do
      post admin_regions_path, params: { region: { code: "5000000000", name: "제주", level: 1, kind: "시도" } }
      delete admin_region_path(regions(:bangok))
    end
    patch admin_region_path(regions(:bangok)), params: { region: { name: "변경" } }
    assert_equal "반곡동", regions(:bangok).reload.name
  end

  test "index offers the add button with the filtered region as the default parent" do
    get admin_regions_path(region_id: regions(:ulleung).id)

    assert_select "a[href=?]", new_admin_region_path(parent_id: regions(:ulleung).id), text: "지역 추가"
  end

  test "show displays the region details, bounds, counts and actions" do
    region = regions(:ulleung)
    get admin_region_path(region)

    assert_response :ok
    assert_select "div", text: "경상북도 울릉군"
    assert_select "a[href=?]", admin_region_path(regions(:gyeongbuk)), text: "경상북도"
    assert_select "[data-role=bounds] [data-column=south]", text: /37\.4/
    assert_select "[data-role=bounds] [data-column=east]", text: /131\.0/
    assert_select "[data-column=children]", text: "1"
    assert_select "a[href=?]", admin_regions_path(region_id: region.id), text: "하위 지역 보기"
    assert_select "a[href=?]", edit_admin_region_path(region), text: "수정"
    assert_select "form[action=?] input[name=_method][value=delete]", admin_region_path(region)
    assert_select "form[action=?] button", admin_region_path(region), text: "삭제"
  end

  test "show renders a read-only map with the region's own and fallback bounds" do
    region = regions(:ulleung)
    get admin_region_path(region)

    assert_select "[data-controller=region-view-map][data-region-view-map-own-bounds-value=?][data-region-view-map-fallback-bounds-value=?]",
                  region.own_bounds.to_json, region.bounds.to_json do
      assert_select "[data-region-view-map-target=canvas]"
    end
  end

  test "show passes empty own bounds but the ancestor bounds for a region without its own" do
    region = regions(:ulleung_eup)
    get admin_region_path(region)

    assert_select "[data-controller=region-view-map][data-region-view-map-own-bounds-value=?]", "[]"
    assert_select "[data-controller=region-view-map][data-region-view-map-fallback-bounds-value=?]", regions(:ulleung).bounds.to_json
  end

  test "show for a region without bounds says so and mentions the ancestor fallback" do
    get admin_region_path(regions(:ulleung_eup))

    assert_select "[data-role=bounds]", text: /없음 \(가까운 상위 지역의 영역을 씁니다\)/
    assert_select "[data-role=children] a", count: 0
  end

  test "show of an unknown region is not found" do
    get admin_region_path(0)

    assert_response :not_found
  end

  test "show requires an operator" do
    delete session_path
    get admin_region_path(regions(:ulleung))

    assert_redirected_to new_session_path
  end

  test "index shows data attribution" do
    get admin_regions_path

    assert_response :success
    assert_select "p", text: /국토교통부 법정동코드.*브이월드\(국토교통부\) 법정구역정보 \(CC BY\)/
  end

  private

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
