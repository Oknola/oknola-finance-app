# Modified by Cardona Labs, LLC, 2026-11-07, AGPL-3.0
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

  test "dashboard touch controls include coarse-pointer target sizes" do
    sign_in users(:family_admin)
    get root_path

    assert_response :success
    assert_select "[aria-label='Choose Business or Personal'] button[class*='max-lg:min-h-11']", count: 2
    assert_select "button[data-dashboard-section-target='button'][class*='max-lg:w-11'][class*='max-lg:h-11']", minimum: 1
    assert_select "button[class*='max-lg:min-h-11']", minimum: 3
  end
end
