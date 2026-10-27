require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "redirects anonymous visitors to sign in" do
    get admin_root_path

    assert_redirected_to new_session_path
  end

  test "keeps non-operators out" do
    member = User.create!(email_address: "member@example.com", password: "password123")
    sign_in_as(member)

    get admin_root_path

    assert_redirected_to root_path
  end

  test "shows counts, running trips and recent stop visits" do
    sign_in_as(users(:operator))

    get admin_root_path

    assert_response :ok
    assert_select "section", text: /운행 중인 버스/
    assert_select "td", text: buses(:one).license_plate
    assert_select "td", text: stops(:market).name
    assert_select "td", text: "정차 중"
  end
end
