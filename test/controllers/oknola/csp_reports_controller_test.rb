# Modified by Cardona Labs, LLC, 2026-11-06, AGPL-3.0
require "test_helper"

class Oknola::CspReportsControllerTest < ActionDispatch::IntegrationTest
  setup { ensure_tailwind_build }

  test "HTML pages use enforcing CSP and nonce every inline script" do
    get new_session_path
    assert_response :success
    sign_in_nonce = assert_enforced_policy_and_inline_nonces

    get new_session_path
    assert_response :success
    assert_equal sign_in_nonce, assert_enforced_policy_and_inline_nonces

    other_session = open_session
    other_session.get new_session_path
    assert_equal 200, other_session.response.status
    other_nonce = other_session.response.headers["Content-Security-Policy"][/nonce-([^']+)/, 1]
    assert_not_equal sign_in_nonce, other_nonce

    sign_in users(:family_admin)
    get root_path

    assert_response :success
    assert_equal sign_in_nonce, assert_enforced_policy_and_inline_nonces

    session = users(:family_admin).sessions.order(:created_at).last
    delete session_path(session)
    get new_session_path

    assert_response :success
    assert_equal sign_in_nonce, assert_enforced_policy_and_inline_nonces
  end

  test "turbo stream responses receive an enforcing CSP nonce" do
    sign_in users(:family_admin)

    post categories_path(format: :turbo_stream), params: {
      category: { name: "CSP Turbo Stream", color: Category::COLORS.first }
    }

    assert_response :success
    assert_match(/script-src[^;]*nonce-/, response.headers["Content-Security-Policy"])
  end

  test "non-HTML responses do not create a CSP nonce session" do
    client = open_session
    client.get api_v1_transactions_url(format: :json)

    assert_equal 401, client.response.status
    refute_includes client.response.headers.fetch("Set-Cookie", ""), Rails.application.config.session_options[:key]
    assert_no_match(/nonce-/, client.response.headers["Content-Security-Policy"])
  end

  test "PostHog script and connect sources include the loader host when enabled" do
    get new_session_path

    policy = response.headers["Content-Security-Policy"]
    connect_src = policy.split(";").find { |directive| directive.strip.start_with?("connect-src") }
    script_src = policy.split(";").find { |directive| directive.strip.start_with?("script-src") }
    posthog = Rails.configuration.x.posthog

    if posthog.api_key.present?
      loader_host = posthog.host.sub(%r{\.i\.posthog\.com(?=[:/]|$)}, "-assets.i.posthog.com")
      assert_includes connect_src, posthog.host
      assert_includes connect_src, loader_host
      assert_includes script_src, loader_host
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
      post "#{oknola_csp_reports_path}?account_id=secret", params: report.to_json, headers: { "CONTENT_TYPE" => "application/csp-report" }
    end

    assert_response :no_content
    all_logs = log_messages.compact.join("\n")
    assert_includes all_logs, "[CSP] script-src-elem bank.example /dashboard"
    assert_not_includes all_logs, "?account_id=secret"
    assert_not_includes all_logs, "account_id"
    refute_includes response.headers.fetch("Set-Cookie", ""), Rails.application.config.session_options[:key]
    assert_no_match(/nonce-/, response.headers["Content-Security-Policy"])
  end

  test "malformed and oversized CSP reports are ignored" do
    log_messages = []
    oversized_report = {
      "csp-report" => {
        "violated-directive" => "script-src-elem",
        "blocked-uri" => "https://bank.example/script.js",
        "document-uri" => "https://finance.example/dashboard"
      },
      "padding" => "x" * Oknola::CspReportsController::MAX_BODY_BYTES
    }.to_json
    assert_operator oversized_report.bytesize, :>, Oknola::CspReportsController::MAX_BODY_BYTES
    assert_kind_of Hash, JSON.parse(oversized_report)

    Rails.logger.stub(:info, ->(message = nil, &block) { log_messages << (message || block&.call) }) do
      post oknola_csp_reports_path, params: "", headers: { "CONTENT_TYPE" => "application/csp-report" }
      assert_response :no_content

      post oknola_csp_reports_path, params: "{", headers: { "CONTENT_TYPE" => "application/csp-report" }
      assert_response :no_content

      post oknola_csp_reports_path, params: oversized_report, headers: { "CONTENT_TYPE" => "application/csp-report" }
      assert_response :no_content
    end

    assert_empty log_messages.grep(/\A\[CSP\]/)
  end

  test "mailto blocked URIs and invalid UTF-8 directives are ignored" do
    log_messages = []
    mailto_report = {
      "csp-report" => {
        "violated-directive" => "img-src",
        "blocked-uri" => "mailto:",
        "document-uri" => "https://finance.example/dashboard"
      }
    }

    Rails.logger.stub(:info, ->(message = nil, &block) { log_messages << (message || block&.call) }) do
      post oknola_csp_reports_path, params: mailto_report.to_json, headers: { "CONTENT_TYPE" => "application/csp-report" }
      assert_response :no_content

      invalid_report = {
        "csp-report" => {
          "violated-directive" => "\xFF".dup.force_encoding(Encoding::UTF_8),
          "blocked-uri" => "https://bank.example",
          "document-uri" => "https://finance.example/dashboard"
        }
      }
      Oknola::CspReportsController.any_instance.stubs(:parse_report).returns(invalid_report)
      post oknola_csp_reports_path, params: "{}", headers: { "CONTENT_TYPE" => "application/csp-report" }
      assert_response :no_content
    end

    assert_empty log_messages.grep(/\A\[CSP\]/)
  end

  test "CSP report route does not accept a format suffix" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/oknola/csp_reports.json", method: :post)
    end
  end

  private
    def assert_enforced_policy_and_inline_nonces
      policy = response.headers["Content-Security-Policy"]
      assert policy.present?
      assert_nil response.headers["Content-Security-Policy-Report-Only"]
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
      assert_not_includes directives["script-src"], "'unsafe-inline'"
      assert_not_includes directives["script-src"], "'unsafe-eval'"
      assert_includes directives["img-src"], "data:"
      assert_includes directives["img-src"], "https:"
      assert_includes directives["img-src"], "blob:"
      assert_includes directives["font-src"], "data:"
      assert_includes directives["script-src"], "https://cdn.plaid.com"
      assert_includes directives["frame-src"], "https://cdn.plaid.com"
      assert_includes directives["connect-src"], "https://*.plaid.com"
      assert_not_includes directives["connect-src"], "https://cdn.plaid.com"
      assert_not_includes directives.keys, "form-action"
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
