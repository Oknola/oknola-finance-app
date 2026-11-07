# Modified by Cardona Labs, LLC, 2026-11-07, AGPL-3.0
require "application_system_test_case"

class Oknola::MobileTargetsTest < ApplicationSystemTestCase
  test "mobile controls fit in plain and embedded layouts" do
    user = users(:family_admin)
    user.update!(preferences: (user.preferences || {}).merge("preview_features_enabled" => true))
    page.current_window.resize_to(375, 812)
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
      assert_no_page_overflow

      visit new_transaction_path
      assert_selector "#entry_amount:focus"
      assert_target "[data-money-field-operator-param='+']"
      assert_no_page_overflow

      visit settings_providers_path
      assert_target "[data-providers-filter-target='chip'][data-kind='all']"
      assert_no_page_overflow
    end
  ensure
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

    def assert_no_page_overflow
      widths = page.evaluate_script("({ scroll: document.documentElement.scrollWidth, client: document.documentElement.clientWidth })")
      assert_operator widths.fetch("scroll"), :<=, widths.fetch("client"), widths.inspect
    end
end
