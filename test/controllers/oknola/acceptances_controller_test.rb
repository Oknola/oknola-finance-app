require "test_helper"

class Oknola::AcceptancesControllerTest < ActionDispatch::IntegrationTest
  SECRET = "test-oknola-handoff-secret-0123456789abcdef".freeze
  SUB = "4f1c2a9e-0000-4000-8000-00000000c6c6".freeze
  EMAIL = "oknola.notice@example.com".freeze

  setup do
    # Handoff codes live in the cache; the test environment's :null_store
    # would drop them.
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @original_secret = ENV["OKNOLA_HANDOFF_SECRET"]
    ENV["OKNOLA_HANDOFF_SECRET"] = SECRET
  end

  teardown do
    Rails.cache = @original_cache
    ENV["OKNOLA_HANDOFF_SECRET"] = @original_secret
  end

  test "a new handoff user is redirected to the notice" do
    sign_in_through_handoff

    get root_path

    assert_redirected_to oknola_notice_path
  end

  test "the notice shows the early-access text, one checkbox and one button" do
    sign_in_through_handoff

    get oknola_notice_path

    assert_response :success
    assert_select "h1", text: I18n.t("oknola.acceptances.show.title")
    assert_select "form[action='#{oknola_notice_path}'] input[type=checkbox][name=accepted][required]", count: 1
    assert_select "form[action='#{oknola_notice_path}'] button[type=submit]", count: 1
    assert_includes response.body, "Settings → Exports downloads everything as CSV and NDJSON"
  end

  test "after accepting, home renders and the notice is not shown again" do
    sign_in_through_handoff

    assert_difference -> { Oknola::Acceptance.count }, 1 do
      post oknola_notice_path, params: { accepted: "1" }
    end
    assert_redirected_to root_path

    follow_redirect!
    assert_response :success

    get oknola_notice_path
    assert_redirected_to root_path
  end

  test "accepting records the kind, version and date" do
    sign_in_through_handoff

    travel_to Time.zone.parse("2026-11-03 12:00:00") do
      post oknola_notice_path, params: { accepted: "1" }
    end

    acceptance = Oknola::Acceptance.find_by!(user: oknola_user)
    assert_equal "early_access", acceptance.kind
    assert_equal "1", acceptance.version
    assert_equal Time.zone.parse("2026-11-03 12:00:00"), acceptance.accepted_at
  end

  test "a second acceptance creates no row and keeps the first date" do
    sign_in_through_handoff
    post oknola_notice_path, params: { accepted: "1" }
    first_date = Oknola::Acceptance.find_by!(user: oknola_user).accepted_at

    travel 1.day do
      assert_no_difference -> { Oknola::Acceptance.count } do
        post oknola_notice_path, params: { accepted: "1" }
        Oknola::Acceptance.accept_early_access!(oknola_user)
      end
    end

    assert_equal first_date, Oknola::Acceptance.find_by!(user: oknola_user).accepted_at
  end

  test "an unchecked box records nothing" do
    sign_in_through_handoff

    assert_no_difference -> { Oknola::Acceptance.count } do
      post oknola_notice_path, params: { accepted: "0" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, I18n.t("oknola.acceptances.show.unchecked")

    get root_path
    assert_redirected_to oknola_notice_path
  end

  test "accepting returns to the page that was asked for" do
    sign_in_through_handoff(route: "/transactions?q=1")
    follow_redirect!
    assert_redirected_to oknola_notice_path

    post oknola_notice_path, params: { accepted: "1" }

    assert_redirected_to "/transactions?q=1"
  end

  test "export and settings stay reachable before accepting" do
    sign_in_through_handoff

    get family_exports_path
    assert_response :success

    assert_difference -> { FamilyExport.count }, 1 do
      post family_exports_path
    end
    assert_redirected_to family_exports_path

    get settings_profile_path
    assert_response :success

    assert_not Oknola::Acceptance.exists?(user: oknola_user)
  end

  test "API key requests are not redirected" do
    user = users(:family_admin)
    Oknola::Acceptance.where(user: user).delete_all
    user.api_keys.active.destroy_all
    api_key = ApiKey.create!(
      user: user,
      name: "Notice test key",
      scopes: [ "read" ],
      source: "web",
      display_key: "test_notice_#{SecureRandom.hex(8)}"
    )

    get "/api/v1/accounts", headers: api_headers(api_key)

    assert_response :success
  end

  test "a super admin sees the notice once and is not locked out" do
    admin = users(:sure_support_staff)
    sign_in admin
    Oknola::Acceptance.where(user: admin).delete_all

    get admin_users_path
    assert_redirected_to oknola_notice_path

    get oknola_notice_path
    assert_response :success

    post oknola_notice_path, params: { accepted: "1" }
    assert_redirected_to admin_users_path

    follow_redirect!
    assert_response :success
    assert Oknola::Acceptance.early_access_accepted?(admin)
  end

  private
    def sign_in_through_handoff(**overrides)
      post oknola_handoff_path,
        params: { sub: SUB, email: EMAIL, locale: "en", time_zone: "America/New_York", theme: "light", country: "US" }.merge(overrides),
        headers: { "Authorization" => "Bearer #{SECRET}" },
        as: :json
      assert_response :success

      get oknola_session_path(code: response.parsed_body["code"])
      assert_response :redirect
    end

    def oknola_user
      OidcIdentity.find_by!(provider: "oknola", uid: SUB).user
    end
end
