# Modified by Cardona Labs, LLC, 2026-11-07, AGPL-3.0
require "application_system_test_case"

class Oknola::OauthConfirmationTest < ApplicationSystemTestCase
  setup do
    @user = users(:sure_support_staff)
    @application = Doorkeeper::Application.create!(
      name: "OAuth confirmation test",
      redirect_uri: "https://example.com/callback"
    )
    sign_in @user
  end

  test "application deletion can be cancelled and confirmed" do
    visit "/oauth/applications"

    cancel_then_confirm

    assert_not Doorkeeper::Application.exists?(@application.id)
  end

  test "authorization revocation can be cancelled and confirmed" do
    token = Doorkeeper::AccessToken.create!(
      application: @application,
      resource_owner_id: @user.id,
      scopes: "read"
    )
    visit "/oauth/authorized_applications"

    cancel_then_confirm

    assert token.reload.revoked?
    assert Doorkeeper::Application.exists?(@application.id)
  end

  private
    def cancel_then_confirm
      page.document.synchronize do
        connected = page.evaluate_script(<<~JS)
          !!window.Stimulus.getControllerForElementAndIdentifier(
            document.getElementById("confirm-dialog"), "confirm-dialog"
          )
        JS
        raise Capybara::ExpectationNotMet, "confirm-dialog is not connected" unless connected
      end

      within("tr", text: @application.name) { find("input[type='submit']").click }
      within("#confirm-dialog[open]") { find("button[value='cancel']").click }
      assert_no_selector "#confirm-dialog[open]"
      assert_selector "tr", text: @application.name

      within("tr", text: @application.name) { find("input[type='submit']").click }
      within("#confirm-dialog[open]") { find("button[value='confirm']", visible: true).click }
      assert_no_selector "#confirm-dialog[open]"
      assert_no_selector "tr", text: @application.name
    end
end
