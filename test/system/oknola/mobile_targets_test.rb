# Modified by Cardona Labs, LLC, 2026-11-09, AGPL-3.0
require "application_system_test_case"

class Oknola::MobileTargetsTest < ApplicationSystemTestCase
  include EntriesTestHelper

  test "mobile controls fit in plain and embedded layouts" do
    user = users(:family_admin)
    user.update!(preferences: (user.preferences || {}).merge("preview_features_enabled" => true))
    12.times do |index|
      create_transaction(
        account: accounts(:depository),
        category: categories(:food_and_drink),
        name: "Mobile target #{index}",
        date: Date.current - index.days
      )
    end
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: true)
    sign_in user

    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    [ false, true ].each do |embedded|
      if embedded
        code = SecureRandom.urlsafe_base64(32)
        Rails.cache.write(
          "#{Oknola::HandoffController::CODE_CACHE_PREFIX}#{Digest::SHA256.hexdigest(code)}",
          { user_id: user.id, route: "/" },
          expires_in: 60.seconds
        )
        visit oknola_session_path(code: code)
      else
        visit root_path
      end

      assert_selector "html[data-embedded='#{embedded}']"
      assert_equal 375, page.evaluate_script("window.innerWidth")
      assert_target "[aria-label='Choose Business or Personal'] button", count: 2
      assert_target "button[data-dashboard-section-target='button']"
      assert_target "a[href='#{new_account_path}']", count: 1
      if embedded
        assert_target "nav[data-oknola-nav] a[aria-label]"
      else
        assert_target "nav[data-viewport-target='bottomNav'] a"
        assert_target "nav.relative a:has(> img[src*='logomark-color'])", count: 1
      end
      assert_no_horizontal_scroll

      visit new_transaction_path
      assert_selector "#entry_amount:focus"
      assert_target "[data-money-field-operator-param='+']"
      assert_no_horizontal_scroll

      visit settings_providers_path
      assert_target "[data-providers-filter-target='chip'][data-kind='all']"
      assert_target "#mobile-settings-nav a[href]"
      if embedded
        assert_no_selector "#mobile-settings-nav button[type='submit']"
      else
        assert_target "#mobile-settings-nav button[type='submit']"
      end
      assert_no_horizontal_scroll

      visit account_path(accounts(:loan), tab: "statements")
      assert_target "[role='tablist'] [role='tab']"
      assert_no_horizontal_scroll
      find("[data-action~='app-layout#openMobileSidebar']", visible: :visible).click
      assert_target "#account-sidebar-tabs [role='tablist'] [role='tab']", count: 3
      assert_no_horizontal_scroll

      visit budget_path(Budget.date_to_param(Date.current))
      budget_tabs = all("#main [role='tablist'] [role='tab']", visible: :visible)
      assert_equal 2, budget_tabs.size
      budget_tab_rects = budget_tabs.map do |tab|
        tab.evaluate_script("(() => { const { left, right } = this.getBoundingClientRect(); return { left, right }; })()")
      end
      assert budget_tab_rects.all? { |rect| rect.fetch("left") >= 0 && rect.fetch("right") <= 375 },
        "budget summary tabs should both be visible at 375px: #{budget_tab_rects}"
      assert_operator budget_tab_rects[0].fetch("right"), :<=, budget_tab_rects[1].fetch("left") + 1
      assert_no_horizontal_scroll

      visit transactions_path
      assert_target "#transactions [id*='category_menu_'] [data-DS--popover-target='button']"
      assert_target "nav:has(select#per_page) a[data-turbo-frame='_top']"
      assert_target "nav:has(select#per_page) select#per_page"
      assert_target "#transaction-filters-button"
      find("#transaction-filters-button").click
      assert_target "#transaction-filters-menu [role='tab']"
      assert_filter_tab_content_fits
      assert_no_horizontal_scroll

      visit transactions_path(q: { search: "Mobile target" })
      assert_target "#transaction-search-filters button"
      assert_no_horizontal_scroll

      visit reports_path
      assert_target ".segmented-control.overflow-x-auto .segmented-control__segment", count: 5
      assert_target "[data-section-key] [data-reports-section-target='button']"
      assert_no_horizontal_scroll
      assert_report_segments_do_not_overlap

      visit insights_path
      assert_target "#insights-refresh a, #insights-refresh button"
      assert_no_horizontal_scroll
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") if page&.driver
    Rails.cache = original_cache if original_cache
  end

  private
    def assert_target(selector, count: nil)
      elements = all(selector, visible: :visible)
      assert_equal count, elements.size if count
      assert elements.any?, "No visible controls for #{selector}"
      elements.each do |element|
        rect = element.evaluate_script("(() => { const { width, height } = this.getBoundingClientRect(); return { width, height }; })()")
        assert_operator rect.fetch("width"), :>=, 44, "#{selector}: #{rect}"
        assert_operator rect.fetch("height"), :>=, 44, "#{selector}: #{rect}"
      end
    end

    def assert_no_horizontal_scroll
      overflow = page.evaluate_script(<<~JS)
        (() => {
          const main = document.querySelector("#main");
          const dialog = document.querySelector("dialog[open] [data-DS--dialog-target='content'] > .overflow-auto");
          return {
            doc: document.documentElement.scrollWidth - document.documentElement.clientWidth,
            main: main ? main.scrollWidth - main.clientWidth : 0,
            dialog: dialog ? dialog.scrollWidth - dialog.clientWidth : 0
          };
        })()
      JS

      assert_operator overflow.fetch("doc"), :<=, 1, "document scrolls sideways: #{overflow}"
      assert_operator overflow.fetch("main"), :<=, 1, "main content scrolls sideways: #{overflow}"
      assert_operator overflow.fetch("dialog"), :<=, 1, "dialog content scrolls sideways: #{overflow}"
    end

    def assert_report_segments_do_not_overlap
      segments = page.evaluate_script(<<~JS)
        (() => {
          const track = document.querySelector(".segmented-control.overflow-x-auto");
          return track ? [...track.querySelectorAll(".segmented-control__segment")].map((segment) => {
            const rect = segment.getBoundingClientRect();
            return { left: rect.left, right: rect.right, width: rect.width, text: segment.innerText };
          }) : [];
        })()
      JS

      assert_equal 5, segments.size, "report period segments were not rendered: #{segments}"
      segments.each_cons(2) do |left, right|
        assert_operator left.fetch("right"), :<=, right.fetch("left") + 1,
          "report period segments overlap: #{segments}"
      end
    end

    def assert_filter_tab_content_fits
      tabs = page.evaluate_script(<<~JS)
        [...document.querySelectorAll("#transaction-filters-menu [role='tab']")].map((tab) => {
          const tabRect = tab.getBoundingClientRect();
          const children = [...tab.querySelectorAll("*")].map((child) => {
            const { left, right, top, bottom } = child.getBoundingClientRect();
            return { left, right, top, bottom };
          });
          return {
            text: tab.innerText,
            scrollWidth: tab.scrollWidth,
            clientWidth: tab.clientWidth,
            rect: { left: tabRect.left, right: tabRect.right, top: tabRect.top, bottom: tabRect.bottom },
            children
          };
        })
      JS

      assert_equal 10, tabs.size, "transaction filter tabs were not all rendered: #{tabs}"
      tabs.each do |tab|
        assert_operator tab.fetch("scrollWidth"), :<=, tab.fetch("clientWidth") + 1,
          "filter tab content overflows #{tab.fetch("text").inspect}: #{tab}"
        tab.fetch("children").each do |child|
          rect = tab.fetch("rect")
          assert_operator child.fetch("left"), :>=, rect.fetch("left") - 1,
            "filter tab child extends left of #{tab.fetch("text").inspect}: #{child} / #{rect}"
          assert_operator child.fetch("right"), :<=, rect.fetch("right") + 1,
            "filter tab child extends right of #{tab.fetch("text").inspect}: #{child} / #{rect}"
          assert_operator child.fetch("top"), :>=, rect.fetch("top") - 1,
            "filter tab child extends above #{tab.fetch("text").inspect}: #{child} / #{rect}"
          assert_operator child.fetch("bottom"), :<=, rect.fetch("bottom") + 1,
            "filter tab child extends below #{tab.fetch("text").inspect}: #{child} / #{rect}"
        end
      end
    end
end
