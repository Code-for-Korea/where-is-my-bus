require "test_helper"

class Admin::LogoutButtonTest < ActionDispatch::IntegrationTest
  test "관리자 화면 헤더에 로그인한 이메일과 로그아웃 버튼이 있다" do
    sign_in_as(users(:operator))

    get admin_root_path

    assert_select "header form[action=?][method=post]", session_path do
      assert_select "input[name=_method][value=delete]"
      assert_select "button", text: "로그아웃"
    end
    assert_select "header", text: /#{Regexp.escape(users(:operator).email_address)}/
  end

  test "로그아웃하면 세션이 끝나고 관리자 화면은 다시 로그인을 요구한다" do
    sign_in_as(users(:operator))

    assert_difference -> { Session.count }, -1 do
      delete session_path
    end
    assert_redirected_to new_session_path

    get admin_root_path
    assert_redirected_to new_session_path
  end
end
