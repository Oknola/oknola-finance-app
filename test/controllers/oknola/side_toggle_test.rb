# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
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
    @business_entries = [
      create_transaction(name: "Business one", tags: [ @business ]),
      create_transaction(name: "Business two", tags: [ @business ])
    ]
    @personal_entry = create_transaction(name: "Personal one", tags: [ @personal ])
    @untagged_entry = create_transaction(name: "Unassigned")
  end

  test "side filters rows and summary and All restores every transaction" do
    get transactions_path(q: { tags: [ "Business" ] }, page: 1)

    assert_response :success
    assert_select "#total-transactions", text: "2"
    assert_rows @business_entries
    assert_rows [ @personal_entry, @untagged_entry ], present: false
    @business_entries.each { |entry| assert_side_chip entry, "Business" }
    @business_entries.each do |entry|
      assert_no_side_chip entry, "Personal"
    end

    all_href = nil
    assert_select "[aria-label='Show transactions by side'] a[href=?]",
                  transactions_path(q: { tags: [ "Personal" ] }, page: 1), text: "Personal"
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
    get transactions_path(q: { tags: [ "Personal" ] }, page: 1)

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
                  transactions_path(q: { tags: [ "Business" ] }, page: 1), text: "Business"
  end

  test "side toggle and chips are absent when both side tags are not available" do
    @personal.destroy!

    get transactions_path(page: 1)

    assert_response :success
    assert_select "#total-transactions", text: "4"
    assert_select "[aria-label='Show transactions by side']", count: 0
    [ *@business_entries, @personal_entry, @untagged_entry ].each do |entry|
      assert_no_side_chip entry, "Business"
      assert_no_side_chip entry, "Personal"
    end
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

    def assert_no_side_chip(entry, side)
      assert_select "turbo-frame##{dom_id(entry)} .flex-shrink-0 > span[title='#{side}']", count: 0
    end
end
