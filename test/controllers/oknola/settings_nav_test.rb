# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
require "test_helper"

class Oknola::SettingsNavTest < ActionDispatch::IntegrationTest
  test "family admins see Finance settings links without Oknola-owned links" do
    sign_in users(:family_admin)

    get settings_preferences_url

    assert_response :success
    [
      accounts_path,
      settings_providers_path,
      settings_preferences_path,
      settings_appearance_path,
      settings_about_path,
      settings_guides_path
    ].each do |path|
      assert_select "nav a[href='#{path}']", count: 2
    end
    [
      settings_profile_path,
      settings_security_path,
      settings_payment_path,
      changelog_path,
      feedback_path
    ].each do |path|
      assert_select "nav a[href='#{path}']", count: 0
    end
    assert_select "nav a[href='#{settings_ai_prompts_path}']", count: 2
  end

  test "super admins keep advanced links and can still open security settings" do
    sign_in users(:sure_support_staff)

    get settings_preferences_url

    assert_response :success
    assert_select "nav a[href='#{admin_system_health_path}']", count: 2
    assert_select "nav a[href='#{settings_security_path}']", count: 0

    get settings_security_url

    assert_response :success
  end

  test "family members do not see the advanced section" do
    sign_in users(:family_member)

    get settings_preferences_url

    assert_response :success
    assert_select "nav section h3", text: "Advanced", count: 0
  end
end
