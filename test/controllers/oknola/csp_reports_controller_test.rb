require "test_helper"

class Oknola::CspReportsControllerTest < ActionDispatch::IntegrationTest
  setup { ensure_tailwind_build }

  test "HTML pages use report-only CSP and nonce every inline script" do
    get new_session_path
    assert_response :success
    sign_in_nonce = assert_report_only_policy_and_inline_nonces

    sign_in users(:family_admin)
    get root_path

    assert_response :success
    dashboard_nonce = assert_report_only_policy_and_inline_nonces
    assert_not_equal sign_in_nonce, dashboard_nonce
  end

  test "connect-src includes the configured PostHog host when enabled" do
    get new_session_path

    policy = response.headers["Content-Security-Policy-Report-Only"]
    connect_src = policy.split(";").find { |directive| directive.strip.start_with?("connect-src") }
    assert connect_src.present?
    posthog = Rails.configuration.x.posthog

    if posthog.api_key.present?
      assert_includes connect_src, posthog.host
    else
      assert_not_includes connect_src, posthog.host
    end
  end

  test "a CSP report logs only the directive, blocked host, and document path" do
    log_messages = []
    report = {
      "csp-report" => {
        "violated-directive" => "script-src-elem",
        "blocked-uri" => "https://bank.example/script.js?account_id=secret",
        "document-uri" => "https://finance.example/dashboard?account_id=secret"
      }
    }

    Rails.logger.stub(:info, ->(message = nil, &block) { log_messages << (message || block&.call) }) do
      post "#{oknola_csp_reports_path}?account_id=secret", params: report.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :no_content
    assert_equal [ "[CSP] script-src-elem bank.example /dashboard" ], log_messages.grep(/\A\[CSP\]/)
  end

  test "malformed and oversized CSP reports are ignored" do
    log_messages = []

    Rails.logger.stub(:info, ->(message = nil, &block) { log_messages << (message || block&.call) }) do
      post oknola_csp_reports_path, params: "", headers: { "CONTENT_TYPE" => "application/json" }
      assert_response :no_content

      post oknola_csp_reports_path, params: "{", headers: { "CONTENT_TYPE" => "application/json" }
      assert_response :no_content

      post oknola_csp_reports_path, params: "x" * (Oknola::CspReportsController::MAX_BODY_BYTES + 1), headers: { "CONTENT_TYPE" => "application/json" }
      assert_response :no_content
    end

    assert_empty log_messages.grep(/\A\[CSP\]/)
  end

  private
    def assert_report_only_policy_and_inline_nonces
      policy = response.headers["Content-Security-Policy-Report-Only"]
      assert policy.present?
      assert_nil response.headers["Content-Security-Policy"]
      assert_match(/script-src[^;]*nonce-/, policy)

      directives = policy.split(";").to_h do |directive|
        name, *sources = directive.strip.split
        [ name, sources ]
      end
      assert_equal [ "'self'" ], directives["default-src"]
      assert_equal [ "'self'" ], directives["base-uri"]
      assert_equal [ "'none'" ], directives["object-src"]
      assert_equal [ "'none'" ], directives["frame-ancestors"]
      assert_includes directives["style-src"], "'unsafe-inline'"
      assert_includes directives["img-src"], "data:"
      assert_includes directives["img-src"], "https:"
      assert_includes directives["font-src"], "data:"
      assert_includes directives["script-src"], "https://cdn.plaid.com"
      assert_includes directives["frame-src"], "https://cdn.plaid.com"
      assert_includes directives["connect-src"], "https://cdn.plaid.com"
      assert_includes directives["report-uri"], "/oknola/csp_reports"

      nonce = policy[/nonce-([^']+)/, 1]
      assert nonce.present?

      inline_scripts = css_select("script:not([src])")
      assert_predicate inline_scripts, :present?
      inline_scripts.each { |script| assert_equal nonce, script["nonce"] }
      assert_select "script:not([src]):not([nonce])", count: 0

      nonce
    end
end
