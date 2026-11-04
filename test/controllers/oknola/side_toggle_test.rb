# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "test_helper"

class Oknola::SideToggleTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper
  include ActionView::RecordIdentifier

  setup do
    sign_in @user = users(:family_admin)
    Entry.delete_all
    @family = @user.family
    @business = @family.tags.create!(name: "Business")
    @personal = @family.tags.create!(name: "Personal")
    accounts(:depository).update!(oknola_side: "business")
    @business_entries = [
      create_transaction(name: "Business one"),
      create_transaction(name: "Business two")
    ]
    @personal_entry = create_transaction(account: accounts(:credit_card), name: "Personal one")
    @untagged_entry = create_transaction(name: "Unassigned")
  end

  test "side filters rows and summary and All restores every transaction" do
    get transactions_path(q: { side: "business" }, page: 1)

    assert_response :success
    assert_select "#total-transactions", text: "3"
    assert_rows [ *@business_entries, @untagged_entry ]
    assert_rows [ @personal_entry ], present: false
    [ *@business_entries, @untagged_entry ].each { |entry| assert_side_chip entry, "Business" }

    all_href = nil
    assert_select "[aria-label='Show transactions by side'] a[href=?]",
                  transactions_path(q: { side: "personal" }, page: 1), text: "Personal"
    assert_select "[aria-label='Show transactions by side'] a[aria-current='true']",
                  text: "Business"
    assert_select "[aria-label='Show transactions by side'] a", text: "All" do |links|
      all_href = links.first["href"]
    end
    assert_equal transactions_path(page: 1), all_href

    get all_href

    assert_response :success
    assert_select "#total-transactions", text: "4"
    assert_rows [ *@business_entries, @personal_entry, @untagged_entry ]
  end

  test "Personal filter and All state are reflected in the control" do
    get transactions_path(q: { side: "personal" }, page: 1)

    assert_response :success
    assert_select "#total-transactions", text: "1"
    assert_rows [ @personal_entry ]
    assert_side_chip @personal_entry, "Personal"
    assert_rows [ *@business_entries, @untagged_entry ], present: false

    get transactions_path(page: 1)

    assert_response :success
    assert_select "#total-transactions", text: "4"
    assert_select "[aria-label='Show transactions by side'] a[aria-current='true']", text: "All"
    assert_select "[aria-label='Show transactions by side'] a[href=?]",
                  transactions_path(q: { side: "business" }, page: 1), text: "Business"
  end

  test "side toggle and chips are available without side tags" do
    @personal.destroy!
    @business.destroy!

    get transactions_path(page: 1)

    assert_response :success
    assert_select "#total-transactions", text: "4"
    assert_select "[aria-label='Show transactions by side']"
    [ *@business_entries, @untagged_entry ].each { |entry| assert_side_chip entry, "Business" }
    assert_side_chip @personal_entry, "Personal"
  end

  private
    def assert_rows(entries, present: true)
      entries.each do |entry|
        assert_select "turbo-frame##{dom_id(entry)}", count: present ? 1 : 0
      end
    end

    def assert_side_chip(entry, side)
      assert_select "turbo-frame##{dom_id(entry)} .flex-shrink-0 > span[title='#{side}']", count: 1
    end

end
