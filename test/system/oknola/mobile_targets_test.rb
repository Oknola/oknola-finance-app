# Modified by Cardona Labs, LLC, 2026-11-07, AGPL-3.0
require "application_system_test_case"

class Oknola::MobileTargetsTest < ApplicationSystemTestCase
  test "mobile controls fit in plain and embedded layouts" do
    user = users(:family_admin)
    user.update!(preferences: (user.preferences || {}).merge("preview_features_enabled" => true))
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
      assert_no_horizontal_scroll

      visit new_transaction_path
      assert_selector "#entry_amount:focus"
      assert_target "[data-money-field-operator-param='+']"
      assert_no_horizontal_scroll

      visit settings_providers_path
      assert_target "[data-providers-filter-target='chip'][data-kind='all']"
      assert_no_horizontal_scroll

      visit reports_path
      assert_target ".segmented-control.overflow-x-auto .segmented-control__segment", count: 5
      assert_no_horizontal_scroll
      assert_report_segments_do_not_overlap
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
end
