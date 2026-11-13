require "test_helper"

class Admin::RegionChildrenTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:operator)) }

  test "without parent_id returns only active roots with the expected keys" do
    get children_admin_regions_path

    assert_response :ok
    body = response.parsed_body
    assert_equal %w[경상남도 경상북도 경기도 세종특별자치시].sort, body.map { |r| r["name"] }.sort
    assert_equal body.map { |r| r["name"] }, body.sort_by { |r| [ r["level"], r["name"] ] }.map { |r| r["name"] }
    assert_equal %w[bounds has_children id kind level name], body.first.keys.sort
    assert body.all? { |r| r["has_children"] }
    assert_equal regions(:gyeonggi).id, body.find { |r| r["name"] == "경기도" }["id"]
  end

  test "parent_id returns only that parent's active children in order" do
    get children_admin_regions_path(parent_id: regions(:gyeonggi).id)

    assert_response :ok
    assert_equal [ "수원시", "수원시 장안구" ], response.parsed_body.map { |r| r["name"] }
  end

  test "bounds fall back to the nearest ancestor and are null when none exist" do
    get children_admin_regions_path(parent_id: regions(:ulleung).id)
    assert_equal [ [ 37.4, 130.8 ], [ 37.6, 131.0 ] ], response.parsed_body.first["bounds"]

    get children_admin_regions_path(parent_id: regions(:gyeonggi).id)
    assert_nil response.parsed_body.find { |r| r["name"] == "수원시" }["bounds"]
  end

  test "has_children is false for leaves and ignores inactive children" do
    get children_admin_regions_path(parent_id: regions(:gyeonggi).id)
    by_name = response.parsed_body.index_by { |r| r["name"] }
    assert_equal true, by_name["수원시 장안구"]["has_children"]
    assert_equal false, by_name["수원시"]["has_children"]

    Region.create!(code: "4199100000", name: "폐지구", level: 3, kind: "읍면동", parent: regions(:abolished), active: false)
    regions(:abolished).update!(active: true)
    get children_admin_regions_path(parent_id: regions(:gyeonggi).id)
    assert_equal false, response.parsed_body.find { |r| r["name"] == "폐지시" }["has_children"]
  end

  test "unknown parent_id returns 404" do
    get children_admin_regions_path(parent_id: 0)

    assert_response :not_found
  end

  test "unauthenticated requests are redirected to login" do
    delete session_path
    get children_admin_regions_path

    assert_redirected_to new_session_path
  end

  test "non-operator members are rejected" do
    delete session_path
    sign_in_as(User.create!(email_address: "member@example.com", password: "password123", role: :member))
    get children_admin_regions_path

    assert_redirected_to root_path
  end

  test "query count does not grow with the number of rows" do
    parent = regions(:gyeongnam)
    add = lambda do |count, tag|
      count.times do |i|
        child = Region.create!(code: "#{tag}#{i.to_s.rjust(8, '0')}", name: "#{tag}지역#{i}", level: 2, kind: "시군구", parent: parent)
        Region.create!(code: "#{tag}9#{i.to_s.rjust(7, '0')}", name: "#{tag}동#{i}", level: 3, kind: "읍면동", parent: child)
      end
    end

    add.call(3, "가")
    few = count_queries { get children_admin_regions_path(parent_id: parent.id) }
    add.call(10, "나")
    many = count_queries { get children_admin_regions_path(parent_id: parent.id) }

    assert_equal few, many
  end

  private

  def count_queries
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end
end
