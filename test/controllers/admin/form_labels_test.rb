require "test_helper"

# 관리자 폼의 제출 버튼이 영어 기본 문구("Create Stop" 등) 대신 한국어로 나온다.
class Admin::FormLabelsTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:operator)) }

  test "new forms show 등록" do
    [ new_admin_route_path, new_admin_stop_path, new_admin_bus_path ].each do |path|
      get path

      assert_select "input[type=submit][value=?]", "등록", count: 1, message: "#{path}"
    end
  end

  test "edit forms show 저장" do
    [ edit_admin_route_path(routes(:one)), edit_admin_stop_path(stops(:hospital)), edit_admin_bus_path(buses(:one)) ].each do |path|
      get path

      assert_select "input[type=submit][value=?]", "저장", count: 1, message: "#{path}"
    end
  end
end
