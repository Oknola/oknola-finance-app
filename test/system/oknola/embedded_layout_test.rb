# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
require "application_system_test_case"

class Oknola::EmbeddedLayoutTest < ApplicationSystemTestCase
  setup do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @user = users(:family_admin)
    @user.update!(preferences: (@user.preferences || {}).merge("preview_features_enabled" => true))

    code = SecureRandom.urlsafe_base64(32)
    Rails.cache.write(
      "#{Oknola::HandoffController::CODE_CACHE_PREFIX}#{Digest::SHA256.hexdigest(code)}",
      { user_id: @user.id, route: "/" },
      expires_in: 60.seconds
    )
    visit oknola_session_path(code: code)
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "embedded layout keeps compact navigation and removes Oknola-provided controls" do
    assert_selector "html[data-embedded='true']"
    assert_no_selector "[data-testid='user-menu']", visible: :visible
    assert_no_selector "a[href*='discord.gg']", visible: :visible
    assert_no_selector "img[src*='logomark-color']", visible: :visible
    assert_no_selector "[data-controller~='release-highlight']"

    expected_links = %w[Home Transactions Reports Plan Assistant Settings]
    link_hrefs = expected_links.map do |name|
      link = find("ul[data-oknola-nav] a", text: name, visible: :visible)
      link[:href]
    end

    link_hrefs.each do |href|
      visit href
      assert_selector "html[data-embedded='true']"
      status = page.evaluate_async_script(<<~JS)
        const done = arguments[arguments.length - 1];
        fetch(window.location.href).then((response) => done(response.status));
      JS
      assert_equal 200, status, "#{href} should respond successfully"
    end

    visit root_path
    click_button "Toggle privacy mode"
    assert_selector "button[aria-label='Toggle privacy mode'][aria-pressed='true']"

    page.current_window.resize_to(390, 844)
    assert_no_selector "nav.relative img[src*='logomark-color']", visible: :visible
    expected_links.each do |name|
      assert_selector "nav[data-viewport-target='bottomNav'] a", text: name, visible: :visible
    end
  end
end

class Oknola::StandardLayoutTest < ApplicationSystemTestCase
  test "normal layout keeps the original branding, account menu and desktop navigation" do
    user = users(:family_admin)
    user.update!(preferences: (user.preferences || {}).merge("preview_features_enabled" => true))
    sign_in user

    assert_selector "html[data-embedded='false']"
    assert_selector "a:has(> img[src*='logomark-color'])", visible: :visible
    assert_selector "a[href*='discord.gg']", visible: :visible
    assert_selector "[data-testid='user-menu']", count: 2, visible: :all
    assert_selector "[data-testid='user-menu']", visible: :visible
    assert_no_selector "nav.h-full ul a", text: "Settings"
    assert_no_selector "nav.h-full ul a", text: "Assistant"
  end
end
