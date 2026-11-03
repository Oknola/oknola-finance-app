require "test_helper"

class Oknola::LegalRedirectTest < ActionDispatch::IntegrationTest
  setup do
    @original_legal_terms_url = ENV["LEGAL_TERMS_URL"]
    @original_legal_privacy_url = ENV["LEGAL_PRIVACY_URL"]
  end

  teardown do
    restore_legal_urls
    assert_nothing_raised { Rails.application.routes.recognize_path("/terms") }
  end

  test "redirects both legal pages to their configured URLs" do
    with_legal_urls(terms: "https://oknola.com/terms", privacy: "https://oknola.com/privacy") do
      get "/terms"
      assert_response :moved_permanently
      assert_redirected_to "https://oknola.com/terms"

      get "/privacy"
      assert_response :moved_permanently
      assert_redirected_to "https://oknola.com/privacy"
    end
  end

  test "renders the stock pages when both URLs are unset" do
    with_legal_urls(terms: nil, privacy: nil) do
      get "/terms"
      assert_response :success
      assert_select "h1"

      get "/privacy"
      assert_response :success
      assert_select "h1"
    end
  end

  test "redirects only the page with a configured URL" do
    with_legal_urls(terms: "https://oknola.com/terms", privacy: nil) do
      get "/terms"
      assert_response :moved_permanently
      assert_redirected_to "https://oknola.com/terms"

      get "/privacy"
      assert_response :success
    end

    with_legal_urls(terms: nil, privacy: "https://oknola.com/privacy") do
      get "/terms"
      assert_response :success

      get "/privacy"
      assert_response :moved_permanently
      assert_redirected_to "https://oknola.com/privacy"
    end
  end

  private
    def with_legal_urls(terms:, privacy:)
      set_legal_url("LEGAL_TERMS_URL", terms)
      set_legal_url("LEGAL_PRIVACY_URL", privacy)
      Rails.application.reload_routes!
      yield
    ensure
      restore_legal_urls
    end

    def set_legal_url(name, value)
      value.nil? ? ENV.delete(name) : ENV[name] = value
    end

    def restore_legal_urls
      set_legal_url("LEGAL_TERMS_URL", @original_legal_terms_url)
      set_legal_url("LEGAL_PRIVACY_URL", @original_legal_privacy_url)
      Rails.application.reload_routes!
    end
end
