# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
require "test_helper"

class Oknola::SideSwitchTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper
  include ActionView::RecordIdentifier

  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @user.update!(preferences: (@user.preferences || {}).except("oknola_side"))
    Entry.delete_all
    @business_account = accounts(:depository)
    @personal_account = accounts(:credit_card)
    @business_account.update!(oknola_side: "business")

    @business_entries = [
      create_transaction(account: @business_account, amount: -100, name: "Business income"),
      create_transaction(account: @business_account, amount: 30, name: "Business expense")
    ]
    @personal_entries = [
      create_transaction(account: @personal_account, amount: -50, name: "Personal income"),
      create_transaction(account: @personal_account, amount: 20, name: "Personal expense")
    ]
    @business_entries << create_transaction(account: @personal_account, amount: 5, name: "Business override")
    @business_entries.last.transaction.update!(oknola_side: "business")
  end

  test "side switch preference filters transaction rows and summary across requests" do
    get transactions_path

    assert_response :success
    assert_summary(count: "2", income: "$50.00", expense: "$20.00")
    assert_rows @personal_entries
    assert_rows @business_entries, present: false
    assert_switch_active("Personal")
    get transactions_path, params: { q: { side: "business" } }
    assert_summary(count: "2", income: "$50.00", expense: "$20.00")
    assert_rows @personal_entries
    assert_rows @business_entries, present: false
    assert_dashboard_totals(income: "$50.00", expense: "$20.00")
    assert_report_totals(income: "$50.00", expense: "$20.00")

    patch oknola_side_path, params: { side: "business" }, headers: { "HTTP_REFERER" => transactions_path }

    assert_redirected_to transactions_path
    assert_equal 303, response.status
    assert_equal "business", @user.reload.preferences["oknola_side"]

    get transactions_path

    assert_response :success
    assert_summary(count: "3", income: "$100.00", expense: "$35.00")
    assert_rows @business_entries
    assert_rows @personal_entries, present: false
    assert_switch_active("Business")
    assert_dashboard_totals(income: "$100.00", expense: "$35.00")
    assert_report_totals(income: "$100.00", expense: "$35.00")
  end

  test "invalid side is rejected without changing the saved preference" do
    @user.update!(preferences: (@user.preferences || {}).merge("oknola_side" => "personal"))
    patch oknola_side_path, params: { side: "all" }

    assert_response :unprocessable_entity
    assert_equal "personal", @user.reload.preferences["oknola_side"]
  end

  test "transaction side changes invalidate cached totals on the next request" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    get transactions_path
    assert_summary(count: "2", income: "$50.00", expense: "$20.00")
    get reports_path
    assert_response :success

    @business_entries.last.transaction.update!(oknola_side: "personal")

    get transactions_path
    assert_summary(count: "3", income: "$50.00", expense: "$25.00")
    get reports_path
    assert_response :success
    assert_includes response.body, "$50.00"
    assert_includes response.body, "$25.00"
  ensure
    Rails.cache = original_cache
  end

  test "account side changes move flow totals on the next request" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @user.update!(preferences: @user.preferences.merge("oknola_side" => "business"))

    get transactions_path
    assert_summary(count: "3", income: "$100.00", expense: "$35.00")
    get reports_path
    assert_response :success

    Oknola::AccountSide.set(@personal_account, "business")

    get transactions_path
    assert_summary(count: "5", income: "$150.00", expense: "$55.00")
    get reports_path
    assert_response :success
    assert_includes response.body, "$150.00"
    assert_includes response.body, "$55.00"
  ensure
    Rails.cache = original_cache
  end

  test "reports exclude realized gains from the other side" do
    @user.update!(preferences: (@user.preferences || {}).merge("oknola_side" => "business"))
    date = Date.current.beginning_of_month
    account = @family.accounts.create!(
      name: "Personal brokerage",
      balance: 10_000,
      currency: "USD",
      accountable: Investment.new
    )
    security = Security.create!(ticker: "PERS#{SecureRandom.hex(3)}", name: "Personal security")
    account.holdings.create!(
      security: security,
      date: date,
      qty: 5,
      price: 150,
      amount: BigDecimal(750),
      currency: "USD",
      cost_basis: 100
    )
    create_trade(security, account: account, qty: -2, date: date, price: 150, currency: "USD")

    get reports_path

    assert_response :success
    assert_select "[data-testid='realized-gain-line']", text: /#{security.ticker}/, count: 0
  end

  test "the switch appears on dashboard, transactions, and reports without an All option" do
    [ root_path, transactions_path, reports_path ].each do |path|
      get path

      assert_response :success
      assert_select "[aria-label='Choose Business or Personal']" do
        assert_select "button", text: "Business"
        assert_select "button", text: "Personal"
        assert_select "button", text: "All", count: 0
      end
    end
  end

  test "cached account sidebar changes with the selected side on the next request" do
    original_cache = Rails.cache
    original_perform_caching = ActionController::Base.perform_caching
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    ActionController::Base.perform_caching = true
    @business_account.update!(oknola_side: "business")
    @personal_account.update!(oknola_side: "personal")

    get root_path
    assert_response :success
    assert_select "#account-sidebar-tabs a[href=?]", account_path(@personal_account), minimum: 1
    assert_select "#account-sidebar-tabs a[href=?]", account_path(@business_account), count: 0

    @user.update!(preferences: @user.preferences.merge("oknola_side" => "business"))
    get root_path

    assert_response :success
    assert_select "#account-sidebar-tabs a[href=?]", account_path(@business_account), minimum: 1
    assert_select "#account-sidebar-tabs a[href=?]", account_path(@personal_account), count: 0
  ensure
    Rails.cache = original_cache
    ActionController::Base.perform_caching = original_perform_caching
  end

  private
    def assert_summary(count:, income:, expense:)
      assert_select "#total-transactions", text: count
      assert_select "#total-income", text: income
      assert_select "#total-expense", text: expense
    end

    def assert_rows(entries, present: true)
      entries.each do |entry|
        assert_select "turbo-frame##{dom_id(entry)}", count: present ? 1 : 0
      end
    end

    def assert_switch_active(side)
      assert_select "[aria-label='Choose Business or Personal'] button[aria-current='true']", text: side
    end

    def assert_dashboard_totals(income:, expense:)
      get root_path

      assert_response :success
      assert_select "#money-flow-section", text: /#{Regexp.escape(income)}/
      assert_select "#money-flow-section", text: /#{Regexp.escape(expense)}/
    end

    def assert_report_totals(income:, expense:)
      get reports_path

      assert_response :success
      assert_includes response.body, income
      assert_includes response.body, expense
    end
end
