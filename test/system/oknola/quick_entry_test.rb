require "application_system_test_case"

class Oknola::QuickEntrySystemTest < ApplicationSystemTestCase
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

    [ "#entry_amount", "label[for='entry_side_business']", "label[for='entry_side_personal']",
      "[data-select-target='button']", "[data-category-select-target='button']" ].each do |selector|
      field = find(selector)
      assert field.evaluate_script("this.getBoundingClientRect().bottom <= window.innerHeight"), "#{selector} is below the fold"
    end

    take_screenshot
  end

  test "account changes select its side and mixed clears both chips" do
    visit new_transaction_path
    select_ds("Account", accounts(:depository))
    assert_checked_field "entry_side_business", visible: :all

    choose "entry_side_personal", allow_label_click: true
    fill_in "Amount", with: "12.50"
    assert_checked_field "entry_side_personal", visible: :all

    select_ds("Account", accounts(:depository))
    assert_checked_field "entry_side_personal", visible: :all

    select_ds("Account", accounts(:credit_card))
    assert_unchecked_field "entry_side_business", visible: :all
    assert_unchecked_field "entry_side_personal", visible: :all
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

  test "chips are absent when either seeded tag is missing" do
    @personal.destroy!
    visit new_transaction_path

    assert_no_selector "#entry_side_business", visible: :all
    assert_no_selector "#entry_side_personal", visible: :all
  end

  test "Enter saves expense and income with the selected side tag" do
    { "Expense" => 12.5, "Income" => -12.5 }.each do |tab, amount|
      visit new_transaction_path
      click_link tab
      select_ds("Account", accounts(:depository))
      fill_in "Amount", with: "12.50"
      fill_in "Description", with: "Quick #{tab}"
      choose "entry_side_business", allow_label_click: true

      find_field(tab == "Expense" ? "Amount" : "Description").send_keys(:enter)

      assert_no_selector "#entry_amount"
      entry = Entry.order(:created_at).last
      assert_equal "Quick #{tab}", entry.name
      assert_equal amount, entry.amount
      assert_includes entry.transaction.tags, @business
    end
  end

  test "a manual side choice overrides the account default on save" do
    visit new_transaction_path(account_id: accounts(:depository).id)
    assert_checked_field "entry_side_business", visible: :all
    fill_in "Amount", with: "12.50"
    fill_in "Description", with: "Personal purchase"
    choose "entry_side_personal", allow_label_click: true

    find_field("Amount").send_keys(:enter)

    assert_no_selector "#entry_amount"
    assert_equal [ @personal ], Entry.order(:created_at).last.transaction.tags.to_a
  end
end
