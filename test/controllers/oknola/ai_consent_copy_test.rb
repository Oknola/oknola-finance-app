# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
require "test_helper"

class Oknola::AiConsentCopyTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @user.update!(ai_enabled: false)
    sign_in @user
  end

  test "available advisor consent uses Oknola copy and existing enable form" do
    User.any_instance.stubs(:ai_available?).returns(true)

    get chats_url

    assert_response :success
    assert_select "h3", text: "Turn on the advisor"
    assert_select "p", text: /Anthropic's API under Cardona Labs' account/
    assert_select "form[action=?]", user_path(@user) do
      assert_select "input[name='user[ai_enabled]'][value='true']"
      assert_select "input[type='submit'][value='Turn on']"
    end
    assert_select "p", text: "You can turn it off any time in Settings → AI Prompts."
    assert_no_match(/Enable AI Chats|anonymized/, response.body)
  end

  test "unavailable advisor consent explains that it is off without an enable button" do
    User.any_instance.stubs(:ai_available?).returns(false)

    get chats_url

    assert_response :success
    assert_includes response.body, "The advisor is off on this server."
    assert_select "input[type='submit'][value='Turn on']", count: 0
  end
end
