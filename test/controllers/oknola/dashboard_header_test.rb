require "test_helper"

class Oknola::DashboardHeaderTest < ActionDispatch::IntegrationTest
  test "dashboard header uses the compact Oknola scale" do
    user = users(:family_admin)
    sign_in user

    get root_path

    assert_response :ok
    assert_select "h1", text: /#{Regexp.escape(user.first_name)}/ do |headers|
      classes = headers.first["class"].split

      assert_includes classes, "text-xl"
      assert_not_includes classes, "lg:text-3xl"
    end
    assert_select "turbo-frame#dashboard_sections [data-controller='DS--menu']"
    assert_select "a[aria-label=?]", I18n.t("pages.dashboard.customize.start")
    assert_select "a[href='#{new_account_path}']"
  end
end
