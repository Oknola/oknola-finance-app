# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
# frozen_string_literal: true

require "test_helper"

class OauthBasicTest < ActionDispatch::IntegrationTest
  setup do
    ensure_tailwind_build
  end

  test "oauth authorization endpoint requires authentication" do
    oauth_app = Doorkeeper::Application.create!(
      name: "Test API Client",
      redirect_uri: "https://client.example.com/callback",
      scopes: "read"
    )

    get "/oauth/authorize?client_id=#{oauth_app.uid}&redirect_uri=#{CGI.escape(oauth_app.redirect_uri)}&response_type=code&scope=read"

    # Should redirect to login page when not authenticated
    assert_redirected_to new_session_path
  end

  test "oauth client registration is unavailable" do
    assert_no_difference "Doorkeeper::Application.count" do
      post "/register", params: {
        client_name: "Oknola",
        redirect_uris: [ "https://client.example.com/callback" ]
      }.to_json, headers: { "Content-Type" => "application/json" }
    end

    assert_response :not_found
  end

  test "oauth authorization refuses an existing third-party client" do
    oauth_app = Doorkeeper::Application.create!(
      name: "Oknola",
      redirect_uri: "https://client.example.com/callback",
      scopes: "read_write"
    )
    sign_in(users(:family_admin))
    authorization_params = {
      client_id: oauth_app.uid,
      redirect_uri: oauth_app.redirect_uri,
      response_type: "code",
      scope: "read_write"
    }

    ensure_tailwind_build
    assert_no_difference "Doorkeeper::AccessGrant.count" do
      get "/oauth/authorize", params: authorization_params
    end

    assert_response :unauthorized
    assert_includes response.body, I18n.t("doorkeeper.authorizations.error.title")
    assert_not_includes response.body, I18n.t("doorkeeper.authorizations.buttons.authorize")
  end

  test "oauth authorization refuses a same-named client with another redirect uri" do
    oauth_app = Doorkeeper::Application.create!(
      name: MobileDevice::OAUTH_APPLICATION_NAME,
      redirect_uri: "https://client.example.com/callback",
      scopes: "read_write"
    )
    sign_in(users(:family_admin))

    assert_no_difference "Doorkeeper::Application.count" do
      get "/oauth/authorize", params: {
        client_id: oauth_app.uid,
        redirect_uri: oauth_app.redirect_uri,
        response_type: "code",
        scope: "read_write"
      }
    end

    assert_response :unauthorized
    assert_not_includes response.body, I18n.t("doorkeeper.authorizations.buttons.authorize")
  end

  test "oauth authorization refuses POST for an existing third-party client" do
    oauth_app = Doorkeeper::Application.create!(
      name: "Oknola",
      redirect_uri: "https://client.example.com/callback",
      scopes: "read_write"
    )
    sign_in(users(:family_admin))

    assert_no_difference "Doorkeeper::AccessGrant.count" do
      post "/oauth/authorize", params: {
        client_id: oauth_app.uid,
        redirect_uri: oauth_app.redirect_uri,
        response_type: "code",
        scope: "read_write"
      }
    end

    assert_response :unauthorized
    assert_not_includes response.body, I18n.t("doorkeeper.authorizations.buttons.authorize")
  end

  test "oauth authorization still shows consent for Sure Mobile" do
    oauth_app = Doorkeeper::Application.create!(
      name: MobileDevice::OAUTH_APPLICATION_NAME,
      redirect_uri: MobileDevice::CALLBACK_URL,
      scopes: "read_write",
      confidential: false
    )
    sign_in(users(:family_admin))
    ensure_tailwind_build
    verifier = SecureRandom.urlsafe_base64(64)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

    get "/oauth/authorize", params: {
      client_id: oauth_app.uid,
      redirect_uri: oauth_app.redirect_uri,
      response_type: "code",
      scope: "read_write",
      code_challenge: challenge,
      code_challenge_method: "S256"
    }

    assert_response :success
    assert_includes response.body, oauth_app.name
    assert_includes response.body, I18n.t("doorkeeper.authorizations.buttons.authorize")
  end

  test "oauth authorization defaults the Sure Mobile scope when scope is omitted" do
    oauth_app = Doorkeeper::Application.create!(
      name: MobileDevice::OAUTH_APPLICATION_NAME,
      redirect_uri: MobileDevice::CALLBACK_URL,
      scopes: "read_write",
      confidential: false
    )
    sign_in(users(:family_admin))
    ensure_tailwind_build
    verifier = SecureRandom.urlsafe_base64(64)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

    get "/oauth/authorize", params: {
      client_id: oauth_app.uid,
      redirect_uri: oauth_app.redirect_uri,
      response_type: "code",
      code_challenge: challenge,
      code_challenge_method: "S256"
    }

    assert_response :success
    assert_select 'input[name="scope"][value="read_write"]'
    assert_includes response.body, I18n.t("doorkeeper.authorizations.buttons.authorize")
  end

  test "oauth authorization endpoint rejects a deactivated user's existing session" do
    oauth_app = Doorkeeper::Application.create!(
      name: "Test API Client",
      redirect_uri: "https://client.example.com/callback",
      scopes: "read"
    )
    user = users(:family_admin)
    sign_in user
    session_record = user.sessions.order(created_at: :desc).first

    # update_column bypasses callbacks, matching the exact scenario this
    # check exists to defend against (a stale session outliving deactivation).
    user.update_column(:active, false)

    get "/oauth/authorize?client_id=#{oauth_app.uid}&redirect_uri=#{CGI.escape(oauth_app.redirect_uri)}&response_type=code&scope=read"

    assert_redirected_to new_session_path
    assert_not Session.exists?(id: session_record.id), "stale session should be destroyed, not just skipped"
  end

  test "oauth token endpoint refuses a refresh_token exchange after the user is deactivated" do
    oauth_app = Doorkeeper::Application.create!(
      name: "Test API Client",
      redirect_uri: "https://client.example.com/callback",
      scopes: "read_write"
    )
    user = users(:family_admin)

    access_token = Doorkeeper::AccessToken.create!(
      application: oauth_app,
      resource_owner_id: user.id,
      expires_in: 2.hours,
      scopes: "read_write",
      use_refresh_token: true
    )
    refresh_token = access_token.plaintext_refresh_token

    # update_column bypasses callbacks (same idiom as the test above), then
    # explicitly exercises User#revoke_all_access_tokens — the mechanism
    # that actually revokes standard Doorkeeper grants/tokens on
    # deactivation, since this endpoint never goes through our custom
    # Authentication concern or MobileDevice#issue_token! at all.
    user.update_column(:active, false)
    user.revoke_all_access_tokens

    post "/oauth/token", params: {
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: oauth_app.uid,
      client_secret: oauth_app.secret
    }

    assert_response :bad_request
    response_body = JSON.parse(response.body)
    assert_equal "invalid_grant", response_body["error"]
  end

  test "oauth token endpoint exists and handles requests" do
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: "invalid_code",
      redirect_uri: "https://example.com/callback",
      client_id: "invalid_client"
    }

    # Should return 401 for invalid client (correct OAuth behavior)
    assert_response :unauthorized
    response_body = JSON.parse(response.body)
    assert_equal "invalid_client", response_body["error"]
  end

  test "oauth applications can be created" do
    assert_difference("Doorkeeper::Application.count") do
      Doorkeeper::Application.create!(
        name: "Test App",
        redirect_uri: "https://example.com/callback",
        scopes: "read"
      )
    end
  end

  test "doorkeeper configuration is properly set up" do
    # Test that Doorkeeper is configured and working
    assert Doorkeeper.configuration.present?, "Doorkeeper configuration should exist"
    assert_equal 1.year, Doorkeeper.configuration.access_token_expires_in
    assert_equal "read", Doorkeeper.configuration.default_scopes.first.to_s
  end
end
