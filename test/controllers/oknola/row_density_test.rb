# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "test_helper"

class Oknola::RowDensityTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper
  include ActionView::RecordIdentifier

  setup do
    sign_in @user = users(:family_admin)
    Entry.delete_all

    accounts(:depository).update!(oknola_side: "business")
    @entry = create_transaction(name: "Dense transaction")
  end

  test "transaction rows use the dense layout and show the account's business side" do
    get transactions_path(page: 1)

    assert_response :success

    assert_select "#transactions .grid-cols-12.bg-container-inset.px-4.py-2"
    assert_select "#transactions .space-y-4"

    row_selector = "turbo-frame##{dom_id(@entry)} [data-controller='clickable-row']"
    assert_select row_selector do |rows|
      classes = rows.first["class"].split
      assert_includes classes, "min-h-12"
      assert_includes classes, "lg:min-h-9"
      assert_includes classes, "py-1"
      assert_includes classes, "lg:py-0"
      assert_not_includes classes, "lg:py-1"
      assert_not_includes classes, "lg:p-4"
    end
    assert_select "#{row_selector} p.privacy-sensitive.font-mono.text-right"
    assert_select "#{row_selector} img.w-9", count: 0
    assert_select "#{row_selector} .flex-shrink-0 > span[title='Business']", count: 1
  end
end
