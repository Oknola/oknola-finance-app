# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "application_system_test_case"

class Oknola::EmbeddedLayoutTest < ApplicationSystemTestCase
  include EntriesTestHelper

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
    expected_links << "Bills" if has_selector?("nav[data-oknola-nav] a[aria-label='Bills']", visible: :visible)
    link_hrefs = expected_links.map do |name|
      link = find("nav[data-oknola-nav] a[aria-label='#{name}']", visible: :visible)
      assert_equal name, link[:title]
      assert_equal name, link.find(".oknola-nav-label").text
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
    assert_no_selector "nav[data-viewport-target='bottomNav']"
    nav = find("nav[data-oknola-nav]", visible: :visible)
    top_nav = find("nav[data-oknola-mobile-top-nav]", visible: :visible)
    nav_rect = nav.evaluate_script("(() => { const { left, top, right } = this.getBoundingClientRect(); return { left, top, right }; })()")
    top_nav_bottom = top_nav.evaluate_script("this.getBoundingClientRect().bottom")
    assert_operator nav_rect.fetch("left"), :<=, 16
    assert_operator nav_rect.fetch("top"), :>=, top_nav_bottom
    main_left_padding = page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('#main')).paddingLeft)")
    assert_operator main_left_padding, :>=, nav_rect.fetch("right") + 8

    links = all("nav[data-oknola-nav] a[aria-label]", visible: :visible)
    link_rects = links.map do |link|
      link.evaluate_script("(() => { const { left, top, width, height } = this.getBoundingClientRect(); return { left, top, width, height }; })()")
    end
    assert_equal link_rects.map { |rect| rect.fetch("top") }.sort, link_rects.map { |rect| rect.fetch("top") }
    assert_equal 1, link_rects.map { |rect| rect.fetch("left") }.uniq.size
    assert link_rects.all? { |rect| rect.fetch("width") >= 44 && rect.fetch("height") >= 44 }
    assert_nav_labels_fit

    expected_links.each do |name|
      assert_selector "nav[data-oknola-nav] a[aria-label='#{name}']", visible: :visible
    end
  end

  test "embedded desktop navigation floats at the bottom right" do
    @user.update!(show_ai_sidebar: false)
    visit root_path
    page.current_window.resize_to(1280, 800)

    nav = find("nav[data-oknola-nav]", visible: :visible)
    nav_rect = nav.evaluate_script("(() => { const { right, bottom } = this.getBoundingClientRect(); return { right, bottom }; })()")
    viewport = page.evaluate_script("({ width: window.innerWidth, height: window.innerHeight })")

    assert_includes 16..32, viewport.fetch("width") - nav_rect.fetch("right")
    assert_includes 16..40, viewport.fetch("height") - nav_rect.fetch("bottom")
    assert_no_selector "nav.w-\\[84px\\]"

    links = all("nav[data-oknola-nav] a[aria-label]", visible: :visible)
    link_rects = links.map do |link|
      link.evaluate_script("(() => { const { left, top } = this.getBoundingClientRect(); return { left, top }; })()")
    end
    assert_equal 1, link_rects.map { |rect| rect.fetch("top") }.uniq.size
    assert_equal link_rects.map { |rect| rect.fetch("left") }.sort, link_rects.map { |rect| rect.fetch("left") }
    assert_nav_labels_fit
    assert_selector "nav[data-oknola-nav] a[aria-current='page']"
  end

  test "embedded desktop content scrolls clear of the floating navigation" do
    30.times do |index|
      create_transaction(name: "Embedded scroll transaction #{index}", date: index.days.ago.to_date)
    end
    page.current_window.resize_to(1280, 800)
    visit transactions_path

    page.execute_script("const main = document.querySelector('#main'); main.scrollTop = main.scrollHeight")
    row_bottom = page.evaluate_script(<<~JS)
      (() => {
        const rows = document.querySelectorAll('#main [data-controller~="clickable-row"]');
        return rows[rows.length - 1].getBoundingClientRect().bottom;
      })()
    JS
    nav_top = find("nav[data-oknola-nav]").evaluate_script("this.getBoundingClientRect().top")

    assert_operator row_bottom, :<=, nav_top
  end

  test "embedded transaction modal covers the floating navigation" do
    page.current_window.resize_to(1280, 800)
    visit transactions_path
    click_on "New transaction"
    assert_selector "dialog[open]"

    assert_nav_center_outside_nav
  end

  test "embedded transaction drawer covers the floating navigation" do
    create_transaction(name: "Embedded drawer transaction")
    page.current_window.resize_to(1280, 800)
    visit transactions_path
    click_on "Embedded drawer transaction"
    assert_selector "dialog[open]"

    assert_nav_center_outside_nav
  end

  test "mobile account sidebar covers the floating navigation" do
    page.current_window.resize_to(390, 844)
    find("[data-action~='app-layout#openMobileSidebar']").click

    assert_selector "[data-app-layout-target='mobileSidebar']:not(.hidden)", visible: :visible
    assert_nav_center_outside_nav
  end

  test "mobile navigation scrolls when the viewport is too short" do
    page.current_window.resize_to(390, 320)

    metrics = find("nav[data-oknola-nav]").evaluate_script(<<~JS)
      (() => {
        const nav = this;
        const style = getComputedStyle(nav);
        const rect = nav.getBoundingClientRect();
        return {
          bottom: rect.bottom,
          height: rect.height,
          maxHeight: parseFloat(style.maxHeight),
          overflowY: style.overflowY,
          scrollHeight: nav.scrollHeight,
          clientHeight: nav.clientHeight,
          viewportHeight: window.innerHeight
        };
      })()
    JS

    assert_equal "auto", metrics.fetch("overflowY")
    assert_operator metrics.fetch("scrollHeight"), :>, metrics.fetch("clientHeight")
    assert_operator metrics.fetch("height"), :<=, metrics.fetch("maxHeight")
    assert_operator metrics.fetch("bottom"), :<=, metrics.fetch("viewportHeight")
  end

  test "desktop navigation stays clear of the AI sidebar chat input" do
    @user.update!(show_ai_sidebar: true)
    page.current_window.resize_to(1280, 800)
    visit transactions_path

    nav = find("nav[data-oknola-nav]", visible: :visible)
    sidebar = find("[data-app-layout-target='rightSidebar']", visible: :visible)
    nav_rect = nav.evaluate_script("(() => { const { left, top, right, bottom } = this.getBoundingClientRect(); return { left, top, right, bottom }; })()")
    sidebar_left = sidebar.evaluate_script("this.getBoundingClientRect().left")

    assert_operator nav_rect.fetch("right"), :<=, sidebar_left - 8
  end

  private
    # Every button shows its name under the icon, whole: not clipped, not wrapped
    def assert_nav_labels_fit
      labels = page.evaluate_script(<<~JS)
        Array.from(document.querySelectorAll("nav[data-oknola-nav] a .oknola-nav-label")).map((label) => {
          const link = label.closest("a").getBoundingClientRect();
          const text = label.getBoundingClientRect();
          return { text: label.textContent, visible: text.width > 0 && text.height > 0,
                   inside: text.left >= link.left - 0.5 && text.right <= link.right + 0.5,
                   oneLine: text.height < 16 };
        })
      JS
      assert labels.any?, "the nav shows no labels"
      labels.each do |label|
        assert label.fetch("visible"), "#{label.fetch("text")} label is not visible"
        assert label.fetch("inside"), "#{label.fetch("text")} label overflows its button"
        assert label.fetch("oneLine"), "#{label.fetch("text")} label wraps"
      end
    end


    def assert_nav_center_outside_nav
      covered = page.evaluate_script(<<~JS)
        (() => {
          const nav = document.querySelector("nav[data-oknola-nav]");
          const rect = nav.getBoundingClientRect();
          const element = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
          return element && element.closest("nav[data-oknola-nav]") === null;
        })()
      JS

      assert covered
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
