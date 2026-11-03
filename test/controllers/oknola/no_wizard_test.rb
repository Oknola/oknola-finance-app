# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
require "test_helper"

class Oknola::NoWizardTest < ActionDispatch::IntegrationTest
  SECRET = "test-oknola-handoff-secret-0123456789abcdef".freeze
  SUB = "4f1c2a9e-0000-4000-8000-00000000c2c2".freeze
  EMAIL = "oknola.onboarded@example.com".freeze

  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @original_secret = ENV["OKNOLA_HANDOFF_SECRET"]
    ENV["OKNOLA_HANDOFF_SECRET"] = SECRET
    Rails.configuration.stubs(:app_mode).returns("self_hosted".inquiry)
    ApplicationController.any_instance.stubs(:redis_connected?).returns(true)
  end

  teardown do
    Rails.cache = @original_cache
    ENV["OKNOLA_HANDOFF_SECRET"] = @original_secret
  end

  test "a new handoff user lands on the dashboard and cannot reopen onboarding preferences" do
    handoff
    assert_response :success
    code = response.parsed_body["code"]
    Oknola::Acceptance.accept_early_access!(OidcIdentity.find_by!(provider: "oknola", uid: SUB).user)

    get oknola_session_path(code: code)
    assert_redirected_to root_path

    follow_redirect!
    assert_response :success
    assert_select "h1", text: /Welcome back/

    get preferences_onboarding_path
    assert_redirected_to root_path
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
        headers: { "Authorization" => "Bearer" + " #{secret}" },
        as: :json
    end
end
