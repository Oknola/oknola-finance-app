# Modified by Cardona Labs, LLC, 2026-11-08, AGPL-3.0
require "application_system_test_case"

class Oknola::DesktopSidebarLayoutTest < ApplicationSystemTestCase
  include EntriesTestHelper

  test "transaction account link stays clear of the category with both sidebars open" do
    user = users(:family_admin)
    user.update!(show_sidebar: true, show_ai_sidebar: true)
    account = accounts(:depository)
    account.update!(name: "Chase Premier Checking")
    entry = create_transaction(
      account: account,
      category: categories(:food_and_drink),
      name: "Desktop sidebar layout transaction",
      merchant: merchants(:amazon)
    )

    page.driver.browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: 1440,
      height: 1000,
      deviceScaleFactor: 1,
      mobile: false
    )
    sign_in user
    visit transactions_path

    assert_equal 1440, page.evaluate_script("window.innerWidth")
    assert_selector "[data-app-layout-target='rightSidebar'].w-full", visible: true

    row = find("##{dom_id(entry)}", visible: true)
    merchant = row.find("span", text: "#{entry.entryable.merchant.name} •", exact: true)
    account_link = row.find("a[href='#{account_path(account, tab: "transactions")}']", visible: true)
    category = row.find("[id='#{dom_id(entry.entryable, "category_menu_desktop")}']", visible: true)
    merchant_rect = rect_for(merchant)
    account_rect = rect_for(account_link)
    category_rect = rect_for(category)
    row_height = row.evaluate_script("this.getBoundingClientRect().height")

    assert_in_delta merchant_rect.fetch("top"), account_rect.fetch("top"), 1
    [ merchant_rect, account_rect ].each do |rect|
      intersects_category = rect.fetch("left") < category_rect.fetch("right") &&
        rect.fetch("right") > category_rect.fetch("left") &&
        rect.fetch("top") < category_rect.fetch("bottom") &&
        rect.fetch("bottom") > category_rect.fetch("top")
      assert_not intersects_category, "transaction text intersects the category pill: #{rect} / #{category_rect}"
    end
    assert_operator row_height, :<, 48, "transaction row is too tall: #{row_height}px"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if page&.driver
  end

  test "report summary cards respond to the width available beside the sidebars" do
    user = users(:family_admin)
    user.update!(show_sidebar: true, show_ai_sidebar: true)
    create_transaction(
      account: accounts(:depository),
      category: categories(:food_and_drink),
      name: "Desktop report summary transaction"
    )

    page.driver.browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: 1440,
      height: 1000,
      deviceScaleFactor: 1,
      mobile: false
    )
    sign_in user
    visit reports_path

    assert_equal 1440, page.evaluate_script("window.innerWidth")
    assert_selector "[data-app-layout-target='rightSidebar'].w-full", visible: true
    net_worth_tables = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("[data-section-key='net_worth'] .rounded-lg.shadow-border-xs.bg-container")]
        .map((table) => getComputedStyle(table).overflowX)
    JS
    assert_equal [ "auto", "auto" ], net_worth_tables
    tops = report_summary_card_tops
    assert_equal 4, tops.size
    assert_equal [ 2, 2 ], tops.map(&:round).tally.values.sort,
      "report summary cards should form two rows of two with both sidebars open: #{tops}"

    page.driver.browser.execute_cdp(
      "Emulation.setDeviceMetricsOverride",
      width: 1920,
      height: 1000,
      deviceScaleFactor: 1,
      mobile: false
    )
    visit reports_path

    assert_equal 1920, page.evaluate_script("window.innerWidth")
    tops = report_summary_card_tops
    assert_equal 4, tops.size
    assert_equal 1, tops.map(&:round).uniq.size,
      "report summary cards should share one row in the wide layout: #{tops}"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if page&.driver
  end

  private
    def report_summary_card_tops
      page.evaluate_script(<<~JS)
        (() => {
          const section = document.querySelector("#main section[class~='@container']");
          const grid = section?.firstElementChild;
          return grid ? [...grid.children].map((card) => card.getBoundingClientRect().top) : [];
        })()
      JS
    end

    def rect_for(element)
      element.evaluate_script(<<~JS)
        (() => {
          const { left, right, top, bottom } = this.getBoundingClientRect();
          return { left, right, top, bottom };
        })()
      JS
    end
end
