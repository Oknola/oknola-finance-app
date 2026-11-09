# Modified by Cardona Labs, LLC, 2026-11-08, AGPL-3.0
require "test_helper"

class Oknola::FinanceUiTest < ActionDispatch::IntegrationTest
  test "Finance is the product name outside the About credit" do
    get new_session_path

    assert_response :success
    assert_select "title", text: "Finance"
    assert_select "img[alt='Finance']"
    assert_select "footer p", text: /FOSS Finance \(AGPL-3\.0\)/
    refute_includes response.body, "built on Sure"
  end

  test "settings guide is branded as Finance" do
    sign_in users(:family_admin)

    get settings_guides_path

    assert_response :success
    assert_select "main h1", text: "Welcome to Finance!"
  end

  test "bank sync copy is branded as Finance" do
    sign_in users(:family_admin)

    get settings_providers_path

    assert_response :success
    assert_includes response.body, "flow into Finance automatically."
  end
end
