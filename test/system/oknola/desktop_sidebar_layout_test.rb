# Modified by Cardona Labs, LLC, 2026-11-07, AGPL-3.0
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
      name: "Desktop sidebar layout transaction"
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
    account_link = row.find("a[href='#{account_path(account, tab: "transactions")}']", visible: true)
    category = row.find("[id='#{dom_id(entry.entryable, "category_menu_desktop")}']", visible: true)
    account_rect = rect_for(account_link)
    category_rect = rect_for(category)

    assert_operator account_rect.fetch("right"), :<=, category_rect.fetch("left"),
      "account link overlaps the category cell: #{account_rect} / #{category_rect}"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if page&.driver
  end

  private
    def rect_for(element)
      element.evaluate_script(<<~JS)
        (() => {
          const { left, right, top, bottom } = this.getBoundingClientRect();
          return { left, right, top, bottom };
        })()
      JS
    end
end
