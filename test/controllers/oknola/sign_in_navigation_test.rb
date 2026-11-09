require "test_helper"

class Oknola::SignInNavigationTest < ActionDispatch::IntegrationTest
  test "handoff sessions do not show settings logout controls" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    code = SecureRandom.urlsafe_base64(32)
    Rails.cache.write(
      "#{Oknola::HandoffController::CODE_CACHE_PREFIX}#{Digest::SHA256.hexdigest(code)}",
      { user_id: users(:family_admin).id, route: "/" },
      expires_in: 60.seconds
    )

    get oknola_session_path(code: code)
    assert_redirected_to "/"
    assert session[:oknola_embedded]

    get settings_preferences_path
    assert_response :success
    assert_select "#settings-nav-container form[action^='/sessions/']", count: 0
  ensure
    Rails.cache = original_cache
  end

  test "local administrator sessions retain both settings logout controls" do
    AuthConfig.stubs(:local_login_enabled?).returns(false)
    AuthConfig.stubs(:local_admin_override_enabled?).returns(true)
    sign_in users(:sure_support_staff)
    assert_redirected_to root_path

    get settings_preferences_path
    assert_response :success
    assert_select "#settings-nav-container form[action^='/sessions/']", count: 2 do
      assert_select "button", text: I18n.t("settings.settings_nav.logout")
      assert_select "input[name='_method'][value='delete']"
    end
  end

  [ true, false ].each do |admin_override|
    test "restricted login shows Oknola notice with admin override #{admin_override}" do
      AuthConfig.stubs(:local_login_enabled?).returns(false)
      AuthConfig.stubs(:local_admin_override_enabled?).returns(admin_override)

      get new_session_path
      assert_response :success
      assert_includes response.body, "#{Rails.configuration.x.product_name} opens from Oknola."
      assert_select "a[href='https://oknola.com']", text: "Oknola"
      assert_includes response.body, "and choose #{Rails.configuration.x.product_name} in your apps."
      assert_select "form[action='#{sessions_path}'] input[name='email']", count: admin_override ? 1 : 0
    end
  end

  test "unrestricted login does not show Oknola notice" do
    AuthConfig.stubs(:local_login_enabled?).returns(true)

    get new_session_path
    assert_response :success
    assert_select "a[href='https://oknola.com']", count: 0
    assert_select "form[action='#{sessions_path}'] input[name='email']", count: 1
  end
end
