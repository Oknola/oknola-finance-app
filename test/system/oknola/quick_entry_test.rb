# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "application_system_test_case"

class Oknola::QuickEntrySystemTest < ApplicationSystemTestCase
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @business = @user.family.tags.create!(name: "Business")
    @personal = @user.family.tags.create!(name: "Personal")
    Oknola::AccountSide.set(accounts(:depository), "business")
    sign_in @user
  end

  test "amount is focused and quick capture fields are above the fold" do
    page.current_window.resize_to(1280, 720)
    visit new_transaction_path

    assert_selector "#entry_amount:focus"
    assert_equal "entry_amount", page.evaluate_script("document.activeElement.id")

    calculator_bar = find(".money-field-wrapper [data-money-field-operator-param='+']").ancestor("div.absolute.top-full")
    type_tabs = find("[data-controller='transaction-type-tabs']")
    assert_operator calculator_bar.evaluate_script("this.getBoundingClientRect().bottom"),
                    :<=, type_tabs.evaluate_script("this.getBoundingClientRect().top")

    [ "#entry_amount", "label[for='entry_side_business']", "label[for='entry_side_personal']",
      "[data-select-target='button']", "[data-category-select-target='button']" ].each do |selector|
      field = find(selector)
      assert field.evaluate_script("this.getBoundingClientRect().bottom <= window.innerHeight"), "#{selector} is below the fold"
    end

    take_screenshot
  end

  test "Oknola income quick entry starts on income and saves with its account side" do
    visit "/oknola/new/income"

    assert_selector "[data-transaction-type-tabs-target='tab'][data-nature='inflow'][aria-current='true']"
    assert_selector "#entry_amount:focus"

    select_ds("Account", accounts(:depository))
    assert_checked_field "entry_side_business", visible: :all
    fill_in "Amount", with: "12.50"
    fill_in "Description", with: "Quick Income"
    assert_field "Description", with: "Quick Income"
    choose "entry_side_business", allow_label_click: true

    find_field("Amount").send_keys(:enter)

    assert_no_selector "#entry_amount"
    entry = Entry.order(:created_at).last
    assert_equal "Quick Income", entry.name
    assert_equal(-12.5, entry.amount)
    assert_equal "Business", Oknola::Side.for(entry.transaction)
  end

  test "account changes select its side and a manual choice remains selected" do
    visit new_transaction_path
    select_ds("Account", accounts(:depository))
    assert_checked_field "entry_side_business", visible: :all

    choose "entry_side_personal", allow_label_click: true
    fill_in "Amount", with: "12.50"
    assert_checked_field "entry_side_personal", visible: :all

    select_ds("Account", accounts(:depository))
    assert_checked_field "entry_side_personal", visible: :all

    select_ds("Account", accounts(:credit_card))
    assert_checked_field "entry_side_personal", visible: :all
  end

  test "preselected and hidden accounts initialize their side" do
    @user.update!(default_account_id: accounts(:depository).id)
    visit new_transaction_path
    assert_checked_field "entry_side_business", visible: :all

    visit new_transaction_path(account_id: accounts(:depository).id)
    assert_no_selector "[data-select-target='button']"
    assert_checked_field "entry_side_business", visible: :all

    Oknola::AccountSide.set(accounts(:connected), "personal")
    visit new_transaction_path(account_id: accounts(:connected).id)
    assert_checked_field "entry_side_personal", visible: :all
  end

  test "side choices are available without seeded tags" do
    @personal.destroy!
    @business.destroy!
    visit new_transaction_path

    assert_selector "#entry_side_business", visible: :all
    assert_selector "#entry_side_personal", visible: :all
  end

  test "Enter in Amount saves an expense with the selected side" do
    visit new_transaction_path
    click_link "Expense"
    select_ds("Account", accounts(:depository))
    fill_in "Amount", with: "12.50"
    fill_in "Description", with: "Quick Expense"
    choose "entry_side_business", allow_label_click: true

    find_field("Amount").send_keys(:enter)

    assert_no_selector "#entry_amount"
    entry = Entry.order(:created_at).last
    assert_equal "Quick Expense", entry.name
    assert_equal 12.5, entry.amount
    assert_nil entry.transaction.oknola_side
  end

  test "Enter in Description saves an income with the selected side" do
    visit new_transaction_path
    click_link "Income"
    select_ds("Account", accounts(:depository))
    fill_in "Amount", with: "12.50"
    fill_in "Description", with: "Quick Income"
    choose "entry_side_business", allow_label_click: true

    find_field("Description").send_keys(:enter)

    assert_no_selector "#entry_amount"
    entry = Entry.order(:created_at).last
    assert_equal "Quick Income", entry.name
    assert_equal(-12.5, entry.amount)
    assert_nil entry.transaction.oknola_side
  end

  test "a manual side choice overrides the account default on save" do
    visit new_transaction_path(account_id: accounts(:depository).id)
    assert_checked_field "entry_side_business", visible: :all
    fill_in "Amount", with: "12.50"
    fill_in "Description", with: "Personal purchase"
    choose "entry_side_personal", allow_label_click: true

    find_field("Amount").send_keys(:enter)

    assert_no_selector "#entry_amount"
    assert_equal "personal", Entry.order(:created_at).last.transaction.oknola_side
  end

  test "duplicating and changing accounts keeps tags separate from the side" do
    @user.update!(default_account_id: accounts(:depository).id)
    Oknola::AccountSide.set(accounts(:credit_card), "personal")
    source = create_transaction(account: accounts(:credit_card), tags: [ @personal, tags(:one) ])
    visit new_transaction_path(duplicate_entry_id: source.id, account_id: "")

    assert_checked_field "entry_side_business", visible: :all
    select_ds("Account", accounts(:credit_card))
    assert_checked_field "entry_side_personal", visible: :all
    select_ds("Account", accounts(:depository))
    assert_checked_field "entry_side_business", visible: :all
    find_field("Amount").send_keys(:enter)

    assert_no_selector "#entry_amount"
    saved = Entry.order(:created_at).last
    assert_not_equal source.id, saved.id
    assert_equal [ @personal.id, tags(:one).id ].sort, saved.transaction.tag_ids.sort
    assert_nil saved.transaction.oknola_side
  end

  test "duplicating a Business override on a Personal account preserves the override" do
    account = accounts(:credit_card)
    Oknola::AccountSide.set(account, "personal")
    source = create_transaction(account: account, tags: [ @business ])
    source.transaction.update!(oknola_side: "business")

    visit new_transaction_path(duplicate_entry_id: source.id)

    assert_checked_field "entry_side_business", visible: :all
    find_field("Amount").send_keys(:enter)

    assert_no_selector "#entry_amount"
    saved = Entry.order(:created_at).last
    assert_equal account.id, saved.account_id
    assert_equal "business", saved.transaction.oknola_side
  end

  test "duplicating a Business-tagged transaction keeps the tag as ordinary metadata" do
    source = create_transaction(tags: [ @business, tags(:one) ])
    visit new_transaction_path(duplicate_entry_id: source.id)

    assert_checked_field "entry_side_business", visible: :all
    find_field("Amount").send_keys(:enter)

    assert_no_selector "#entry_amount"
    saved = Entry.order(:created_at).last
    assert_not_equal source.id, saved.id
    assert_equal [ @business.id, tags(:one).id ].sort, saved.transaction.tag_ids.sort
    assert_nil saved.transaction.oknola_side
    saved.transaction.taggings.group(:tag_id).count.each_value do |count|
      assert_equal 1, count
    end
  end
end
