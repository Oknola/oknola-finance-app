require "test_helper"

class Oknola::QuickEntriesControllerTest < ActionDispatch::IntegrationTest
  test "redirects expense and income to the matching transaction form" do
    sign_in users(:family_admin)

    get "/oknola/new/expense"
    assert_redirected_to "/transactions/new?nature=outflow"

    get "/oknola/new/income"
    assert_redirected_to "/transactions/new?nature=inflow"
  end

  test "does not route unsupported kinds" do
    sign_in users(:family_admin)

    get "/oknola/new/transfer"

    assert_response :not_found
  end

  test "requires sign-in" do
    get "/oknola/new/income"

    assert_redirected_to new_session_path
  end
end
