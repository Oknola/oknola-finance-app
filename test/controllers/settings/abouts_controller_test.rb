# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
require "test_helper"

class Settings::AboutsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "shows attribution and links to the running source and licence" do
    Sure.stubs(:commit_sha).returns("0123456789abcdef0123456789abcdef01234567")

    get settings_about_path

    assert_response :success
    assert_select "h1", text: "About"
    assert_select "p", text: "Finance, built on Sure (AGPL-3.0)."
    assert_select "a[href='https://github.com/Oknola/oknola-finance-app/commit/0123456789abcdef0123456789abcdef01234567']", text: "0123456"
    assert_select "a[href$='/blob/oknola/LICENSE']", text: "AGPL-3.0"
    assert_select "p", text: "Not affiliated with or endorsed by Maybe Finance Inc."
  end

  test "links to the fork when the running commit is blank" do
    Sure.stubs(:commit_sha).returns(nil)

    get settings_about_path

    assert_response :success
    assert_select "a[href='https://github.com/Oknola/oknola-finance-app']", text: "oknola branch"
    assert_select "a[href^='https://github.com/Oknola/oknola-finance-app/commit/']", count: 0
  end

  test "profile directs account deletion to Oknola instead of rendering a delete form" do
    get settings_profile_path

    assert_response :success
    assert_select "form[action='#{user_path(users(:family_admin))}'][method='post'] input[name='_method'][value='delete']", count: 0
    assert_select "a[data-turbo-method='delete'][href='#{user_path(users(:family_admin))}']", count: 0
    assert_select "p.text-secondary.text-sm", text: "To delete your account, use Oknola → Settings → Account. Export first: Settings → Exports."
  end
end
