require "test_helper"

class Oknola::HandoffControllerTest < ActionDispatch::IntegrationTest
  SECRET = "test-oknola-handoff-secret-0123456789abcdef".freeze
  SUB = "4f1c2a9e-0000-4000-8000-00000000c1c1".freeze
  EMAIL = "oknola.person@example.com".freeze

  setup do
    # The test environment uses :null_store, which would make every code
    # vanish; a memory store behaves like the production Redis cache here.
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @original_secret = ENV["OKNOLA_HANDOFF_SECRET"]
    ENV["OKNOLA_HANDOFF_SECRET"] = SECRET
  end

  teardown do
    Rails.cache = @original_cache
    ENV["OKNOLA_HANDOFF_SECRET"] = @original_secret
  end

  test "rejects a wrong, missing or non-bearer secret" do
    assert_no_difference [ "User.count", "Family.count" ] do
      handoff(secret: "wrong")
      assert_response :unauthorized

      post oknola_handoff_path, params: handoff_params, as: :json
      assert_response :unauthorized

      post oknola_handoff_path, params: handoff_params, headers: { "Authorization" => "Basic #{SECRET}" }, as: :json
      assert_response :unauthorized
    end
  end

  test "rejects every call when the secret is not configured" do
    ENV["OKNOLA_HANDOFF_SECRET"] = ""

    post oknola_handoff_path, params: handoff_params, headers: { "Authorization" => "Bearer " }, as: :json
    assert_response :unauthorized

    handoff(secret: "")
    assert_response :unauthorized
  end

  test "first handoff creates one family, one admin user without a password, and two tags" do
    assert_difference({ "Family.count" => 1, "User.count" => 1, "OidcIdentity.count" => 1, "Tag.count" => 2 }) do
      handoff
    end

    assert_response :success
    assert_equal "no-store", response.headers["Cache-Control"]
    assert response.parsed_body["code"].present?

    user = oknola_user
    assert_equal EMAIL, user.email
    assert user.admin?
    assert_nil user.password_digest
    assert user.onboarded?
    assert user.set_onboarding_preferences_at.present?
    assert_equal "dark", user.theme
    assert_equal %w[Business Personal], user.family.tags.order(:name).pluck(:name)
    assert_equal "USD", user.family.currency
    assert_equal "America/New_York", user.family.timezone
    assert_equal "US", user.family.country
  end

  test "a handoff user is a family admin even on a fresh instance" do
    # On an instance with no users, Sure's own sign-up path makes the creator
    # the instance super admin.
    User.stubs(:exists?).returns(false)
    assert_equal :super_admin, User.role_for_new_family_creator

    handoff
    assert_response :success

    assert_equal "admin", oknola_user.role
  end

  test "unknown preferences fall back to defaults" do
    handoff(locale: "xx", time_zone: "Not/AZone", theme: "neon", country: "ZZ")
    assert_response :success

    family = oknola_user.family
    assert_equal "en", family.locale
    assert_nil family.timezone
    assert_equal "US", family.country
    assert_equal "USD", family.currency
    assert_equal "system", oknola_user.theme
  end

  test "second handoff for the same sub creates nothing and mints a fresh code" do
    handoff
    first_code = response.parsed_body["code"]

    assert_no_difference [ "Family.count", "User.count", "OidcIdentity.count", "Tag.count" ] do
      handoff
    end

    assert_response :success
    assert_not_equal first_code, response.parsed_body["code"]
  end

  test "an email change in Oknola updates the Finance user" do
    handoff
    handoff(email: "Renamed.Person@Example.com")

    assert_response :success
    assert_equal "renamed.person@example.com", oknola_user.reload.email
  end

  test "an email owned by a Finance user outside Oknola is never merged" do
    existing = users(:family_admin)

    assert_no_difference [ "Family.count", "User.count", "OidcIdentity.count" ] do
      handoff(email: existing.email)
    end

    assert_response :conflict
    assert_not OidcIdentity.exists?(provider: "oknola", uid: SUB)
  end

  test "an inactive user gets 410" do
    handoff
    oknola_user.update_columns(active: false)

    handoff
    assert_response :gone
  end

  test "an invalid request is rejected" do
    handoff(email: "not-an-email")
    assert_response :unprocessable_entity

    handoff(sub: "")
    assert_response :unprocessable_entity
  end

  test "session signs the user in and sets the embedded flag" do
    handoff
    code = response.parsed_body["code"]

    assert_difference -> { oknola_user.sessions.count }, 1 do
      get oknola_session_path(code: code)
    end

    assert_redirected_to "/"
    assert session[:oknola_embedded]
    assert cookies[:session_token].present?
  end

  test "session redirects to the route bound at handoff" do
    handoff(route: "/transactions?q=1")

    get oknola_session_path(code: response.parsed_body["code"])

    assert_redirected_to "/transactions?q=1"
  end

  test "route allowlist refuses anything but an in-app path" do
    [ "//evil.example", "https://evil.example", "/\\evil.example", "\\\\evil.example", "javascript:alert(1)", "/ok\nLocation: x", "relative" ].each do |route|
      handoff(route: route)
      get oknola_session_path(code: response.parsed_body["code"])

      assert_redirected_to "/", "route #{route.inspect} should fall back to /"
      reset!
    end
  end

  test "a replayed code fails" do
    handoff
    code = response.parsed_body["code"]
    get oknola_session_path(code: code)
    reset!

    assert_no_difference -> { Session.count } do
      get oknola_session_path(code: code)
    end

    assert_redirected_to new_session_path
    assert_nil session[:oknola_embedded]
  end

  test "an expired code fails" do
    handoff
    code = response.parsed_body["code"]

    travel 61.seconds do
      assert_no_difference -> { Session.count } do
        get oknola_session_path(code: code)
      end
    end

    assert_redirected_to new_session_path
  end

  test "an unknown or missing code fails" do
    get oknola_session_path(code: "not-a-code")
    assert_redirected_to new_session_path

    get oknola_session_path
    assert_redirected_to new_session_path
  end

  test "a code for a user deactivated after minting fails" do
    handoff
    code = response.parsed_body["code"]
    oknola_user.update_columns(active: false)

    get oknola_session_path(code: code)

    assert_redirected_to new_session_path
  end

  test "an MFA user goes through Sure's MFA step" do
    handoff
    code = response.parsed_body["code"]
    oknola_user.update_columns(otp_required: true, otp_secret: ROTP::Base32.random(32))

    assert_no_difference -> { Session.count } do
      get oknola_session_path(code: code)
    end

    assert_redirected_to verify_mfa_path
    assert_equal oknola_user.id, session[:mfa_user_id]
  end

  test "no email, secret or code appears in a log line" do
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)

    begin
      handoff
      code = response.parsed_body["code"]
      get oknola_session_path(code: code)
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end

    log = io.string
    assert_includes log, "/oknola/session"
    assert_not_includes log, EMAIL
    assert_not_includes log, SECRET
    assert_not_includes log, code
  end

  private
    def handoff_params(**overrides)
      {
        sub: SUB,
        email: EMAIL,
        locale: "en",
        time_zone: "America/New_York",
        theme: "dark",
        country: "US"
      }.merge(overrides)
    end

    def handoff(secret: SECRET, **overrides)
      post oknola_handoff_path,
        params: handoff_params(**overrides),
        headers: { "Authorization" => "Bearer #{secret}" },
        as: :json
    end

    def oknola_user
      OidcIdentity.find_by!(provider: "oknola", uid: SUB).user
    end
end
