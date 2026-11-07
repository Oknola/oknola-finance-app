require "application_system_test_case"
require "json"

class Oknola::UiWalkTest < ApplicationSystemTestCase
  self.use_transactional_tests = false

  WALK_WIDTHS = [ [ 375, 812 ], [ 1440, 900 ] ].freeze
  PHONE_LAYOUTS = [ false, true ].freeze
  PHONE_THEMES = %w[light dark].freeze
  DESKTOP_CONFIGS = [ [ "light", false ], [ "dark", true ] ].freeze

  setup do
    @walk_email = "ui-walk-#{SecureRandom.hex(4)}@example.com"
    Demo::Generator.new(seed: 42).generate_default_data!(skip_clear: true, email: @walk_email)
    @user = User.find_by!(email: @walk_email)
    @user.update!(password: user_password_test)
    Oknola::Acceptance.accept_early_access!(@user)
    @family = @user.family
    @demo_user = @user
    @empty_email = "ui-walk-empty-#{SecureRandom.hex(4)}@example.com"
    @empty_family = Family.create!(
      name: "UI Walk Empty Family",
      currency: "USD",
      locale: "en",
      country: "US",
      timezone: "America/New_York",
      date_format: "%m-%d-%Y"
    )
    @empty_user = @empty_family.users.create!(
      email: @empty_email,
      first_name: "Walker",
      last_name: "Empty",
      role: "admin",
      password: user_password_test,
      onboarded_at: Time.current
    )
    @empty_user.update!(
      ai_enabled: true,
      preferences: @empty_user.preferences.to_h.merge("preview_features_enabled" => true)
    )
    Oknola::Acceptance.accept_early_access!(@empty_user)
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @measurements = []

    @family.accounts.limit(2).each_with_index do |account, index|
      Oknola::AccountSide.set(account, index.zero? ? "business" : "personal")
    end
  end

  teardown do
    write_measurements
    Rails.cache = @original_cache
  end

  test "walks the requested UI matrix and records findings without assertions" do
    install_browser_listeners
    walk_matrix
    walk_empty_reports
    walk_signed_out_page
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    write_measurements
  end

  private

    def walk_matrix
      routes = walk_routes
      WALK_WIDTHS.each do |width, height|
        configurations = if width == 375
          PHONE_THEMES.product(PHONE_LAYOUTS).map { |theme, embedded| [ theme, embedded ] }
        else
          DESKTOP_CONFIGS
        end

        configurations.each do |theme, embedded|
          page.driver.browser.execute_cdp(
            "Emulation.setDeviceMetricsOverride",
            width: width,
            height: height,
            deviceScaleFactor: 1,
            mobile: width == 375
          )
          authenticate_for_layout(embedded)
          @user.update!(theme: theme)

          routes.each do |route|
            walk_route(route, width: width, theme: theme, embedded: embedded)
          end
        end
      end
    end

    def walk_route(route, width:, theme:, embedded:)
      @user.update!(ai_enabled: false) if route.fetch(:name) == "Assistant consent"
      set_side("personal")
      visit route.fetch(:path)
      sides = has_selector?("[aria-label='Choose Business or Personal']", visible: :visible) ? %w[personal business] : [ "personal" ]

      sides.each do |side|
        set_side(side)
        visit route.fetch(:path) if side == "business"
        capture(route.fetch(:name), width, theme, embedded, side)
        open_route_controls(route.fetch(:name), width, theme, embedded, side)
      end
    rescue StandardError => error
      record_error(route.fetch(:name), width, theme, embedded, @user.preferences&.fetch("oknola_side", "personal"), error)
    ensure
      @user.update!(ai_enabled: true) if route.fetch(:name) == "Assistant consent"
    end

    def walk_routes
      rows = [
        [ "Dashboard", root_path ],
        [ "Transactions list", transactions_path ],
        [ "Transaction search", transactions_path(q: { search: "market" }) ],
        [ "Transaction filters", transactions_path(q: { types: [ "expense" ], search: "market" }) ],
        [ "New transaction", new_transaction_path ],
        [ "Quick entry expense", oknola_quick_entry_path(kind: "expense") ],
        [ "Quick entry income", oknola_quick_entry_path(kind: "income") ],
        [ "Accounts list", accounts_path ],
        [ "New account flow", new_account_path ],
        [ "Budgets index", budgets_path ],
        [ "Reports", reports_path ],
        [ "Reports periods", reports_path(period_type: "last_6_months") ],
        [ "Insights feed", insights_path ],
        [ "Assistant chat", chats_path ],
        [ "Assistant consent", chats_path ],
        [ "Assistant new chat", new_chat_path ],
        [ "Goals", goals_path ],
        [ "Rules", rules_path ],
        [ "Auto matches", auto_matches_path ],
        [ "New rule", new_rule_path ],
        [ "Categories", categories_path ],
        [ "Tags", tags_path ],
        [ "Merchants", family_merchants_path ],
        [ "Recurring", recurring_transactions_path ],
        [ "Imports list", imports_path ],
        [ "New import", new_import_path ],
        [ "Exports list", family_exports_path ],
        [ "New export", new_family_export_path ],
        [ "Settings profile", settings_profile_path ],
        [ "Settings preferences", settings_preferences_path ],
        [ "Settings appearance", settings_appearance_path ],
        [ "Settings providers", settings_providers_path ],
        [ "Statement Vault", account_statements_path ],
        [ "Settings hosting", settings_hosting_path ],
        [ "Settings security", settings_security_path ],
        [ "Settings payment", settings_payment_path ],
        [ "Settings API keys", settings_api_keys_path ],
        [ "Settings MCP", settings_mcp_path ],
        [ "Settings AI prompts", settings_ai_prompts_path ],
        [ "Settings guides", settings_guides_path ],
        [ "Settings LLM usage", settings_llm_usage_path ],
        [ "Settings classifier", settings_classifier_path ],
        [ "Settings debug", settings_debug_path ],
        [ "Settings background jobs", settings_background_jobs_path ],
        [ "Settings About", settings_about_path ]
      ].map { |name, path| { name: name, path: path } }

      @family.accounts.to_a.uniq(&:accountable_type).each do |account|
        rows << { name: "Account #{account.accountable_type}", path: account_path(account) }
      end

      @family.budgets.order(:start_date).limit(2).each do |budget|
        month = budget.start_date.strftime("%Y-%m")
        rows << { name: "Budget month #{month}", path: budget_path(month) }
        rows << { name: "Budget edit #{month}", path: edit_budget_path(month) }
        category = budget.budget_categories.first
        if category
          rows << {
            name: "Budget category drill-down #{month}",
            path: budget_budget_category_path(budget_month_year: month, id: category.id)
          }
        end
      end
      rows << { name: "Empty budget month", path: budget_path("2010-01") }

      transaction = @family.entries.where(entryable_type: "Transaction").first
      if transaction
        rows << { name: "Transaction drawer", path: transaction_path(transaction, display: "drawer") }
        rows << { name: "Bulk edit drawer", path: new_transactions_bulk_update_path(bulk_update: { entry_ids: [ transaction.id ] }) }
        rows << { name: "New split", path: new_transaction_split_path(transaction) }
      end

      import = TransactionImport.create!(family: @family)
      rows << { name: "Import mapping configuration", path: import_configuration_path(import) }

      empty_chat = @user.chats.create!(title: "UI walk empty chat")
      rows << { name: "Empty assistant chat", path: chat_path(empty_chat) }
      rows
    end

    def open_route_controls(name, width, theme, embedded, side)
      case name
      when "Dashboard"
        page.execute_script(<<~JS)
          document.querySelectorAll("button[data-dashboard-section-target='button'][aria-expanded='false']")
            .forEach((button) => button.click());
        JS
        capture("Dashboard with every section open", width, theme, embedded, side)
        period_button = all("#dashboard_sections button[aria-label]", visible: :visible).find do |button|
          button[:aria_label].to_s.match?(/period/i)
        end
        if period_button
          period_button.click
          capture("Dashboard period control menu open", width, theme, embedded, side)
        end
      when "Reports", "Reports periods"
        page.execute_script(<<~JS)
          document.querySelectorAll("button[data-reports-section-target='button'][aria-expanded='false']")
            .forEach((button) => button.click());
        JS
        capture("Reports with every section open", width, theme, embedded, side)
      when "Accounts list"
        selector = "[data-action*='app-layout#openMobileSidebar']"
        if has_selector?(selector, visible: :visible)
          find(selector, visible: :visible).click
          capture("Accounts mobile sidebar open", width, theme, embedded, side)
        end
      when "Transactions list"
        toggle = "#toggle-checkboxes-button"
        find(toggle, visible: :visible).click if has_selector?(toggle, visible: :visible)
        checkbox = "input[data-bulk-select-target='row']"
        if has_selector?(checkbox, visible: :all)
          page.execute_script("document.querySelector(arguments[0]).click()", checkbox)
          drawer_link = "a[data-turbo-frame='bulk_transaction_edit_drawer']"
          if has_selector?(drawer_link, visible: :visible)
            find(drawer_link, visible: :visible).click
            capture("Bulk edit drawer open", width, theme, embedded, side)
          end
        end
        visit transactions_path
        row_link = "a[data-clickable-row-target='link'][data-turbo-frame='drawer']"
        if has_selector?(row_link, visible: :visible)
          find(row_link, visible: :visible, match: :first).click
          capture("Selected transaction drawer open", width, theme, embedded, side)
        end
      when "Transaction search", "Transaction filters"
        button = "#transaction-filters-button"
        if has_selector?(button, visible: :visible)
          find(button, visible: :visible).click
          capture("Transaction filters menu open", width, theme, embedded, side)
        end
      end
    rescue StandardError => error
      record_error("#{name} interaction", width, theme, embedded, side, error)
    end

    def authenticate_for_layout(embedded)
      page.driver.browser.manage.delete_all_cookies
      visit new_session_path
      within %(form[action='#{sessions_path}']) do
        find("input[type='email']").set(@user.email)
        find("input[type='password']").set(user_password_test)
        find("[type='submit']").click
      end
      page.document.synchronize do
        unless has_selector?("[data-app-layout-user-id-value='#{@user.id}']")
          raise Capybara::ExpectationNotMet, "generated user did not reach the authenticated layout"
        end
      end
      return visit root_path unless embedded

      code = SecureRandom.urlsafe_base64(32)
      Rails.cache.write(
        "#{Oknola::HandoffController::CODE_CACHE_PREFIX}#{Digest::SHA256.hexdigest(code)}",
        { user_id: @user.id, route: "/" },
        expires_in: 60.seconds
      )
      visit oknola_session_path(code: code)
    end

    def set_side(side)
      @user.update!(preferences: @user.preferences.to_h.merge("oknola_side" => side))
    end

    def walk_signed_out_page
      [ [ 375, 812, "light" ], [ 375, 812, "dark" ], [ 1440, 900, "light" ], [ 1440, 900, "dark" ] ].each do |width, height, theme|
        page.driver.browser.execute_cdp(
          "Emulation.setDeviceMetricsOverride",
          width: width,
          height: height,
          deviceScaleFactor: 1,
          mobile: width == 375
        )
        page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [
          { name: "prefers-color-scheme", value: theme }
        ])
        page.driver.browser.manage.delete_all_cookies
        visit new_session_path
        capture("Signed-out session", width, theme, false, nil)
      rescue StandardError => error
        record_error("Signed-out session", width, theme, false, nil, error)
      end
      page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    end

    def walk_empty_reports
      configurations = [
        [ 375, 812, "light", false ], [ 375, 812, "light", true ],
        [ 375, 812, "dark", false ], [ 375, 812, "dark", true ],
        [ 1440, 900, "light", false ], [ 1440, 900, "dark", true ]
      ]
      @user = @empty_user
      configurations.each do |width, height, theme, embedded|
        page.driver.browser.execute_cdp(
          "Emulation.setDeviceMetricsOverride",
          width: width,
          height: height,
          deviceScaleFactor: 1,
          mobile: width == 375
        )
        @user.update!(theme: theme)
        authenticate_for_layout(embedded)
        visit reports_path
        sides = has_selector?("[aria-label='Choose Business or Personal']", visible: :visible) ? %w[personal business] : [ "personal" ]
        sides.each do |side|
          set_side(side)
          visit reports_path if side == "business"
          capture("Reports empty state", width, theme, embedded, side)
        end
      rescue StandardError => error
        record_error("Reports empty state", width, theme, embedded, nil, error)
      end
    ensure
      @user = @demo_user
    end

    def capture(name, width, theme, embedded, side)
      result = page.evaluate_script(<<~JS)
        (() => {
          const visible = (el) => {
            const style = getComputedStyle(el);
            const rect = el.getBoundingClientRect();
            return rect.width > 0 && rect.height > 0 && style.display !== "none" &&
              style.visibility !== "hidden" && Number(style.opacity) !== 0;
          };
          const delta = (el) => Math.max(0, el.scrollWidth - el.clientWidth);
          const main = document.querySelector("#main");
          const dialog = document.querySelector("dialog[open] [data-DS--dialog-target='content'] > .overflow-auto");
          const controls = [...document.querySelectorAll("a, button, input")].filter(visible).map((el) => {
            const rect = el.getBoundingClientRect();
            return { tag: el.tagName, text: (el.innerText || el.getAttribute("aria-label") || el.value || "").trim().slice(0, 80),
              width: Math.round(rect.width * 10) / 10, height: Math.round(rect.height * 10) / 10 };
          });
          const clippedAll = [...document.querySelectorAll("body *")].filter((el) => {
            if (!visible(el)) return false;
            const style = getComputedStyle(el);
            const text = (el.innerText || "").trim();
            return text && (["hidden", "clip"].includes(style.overflowX) && el.scrollWidth > el.clientWidth + 1 ||
              ["hidden", "clip"].includes(style.overflowY) && el.scrollHeight > el.clientHeight + 1);
          }).map((el) => ({ tag: el.tagName, text: (el.innerText || "").trim().slice(0, 100),
            overflowX: getComputedStyle(el).overflowX, overflowY: getComputedStyle(el).overflowY,
            scrollWidth: el.scrollWidth, clientWidth: el.clientWidth,
            scrollHeight: el.scrollHeight, clientHeight: el.clientHeight }));
          const scrollContainersAll = [...document.querySelectorAll("body *")].filter((el) => {
            const style = getComputedStyle(el);
            return visible(el) && ["auto", "scroll"].includes(style.overflowX) && delta(el) > 1;
          }).map((el) => ({ tag: el.tagName, className: String(el.className).slice(0, 100), overflow: delta(el) }));
          const rgb = (color) => {
            const values = color.match(/[\\d.]+/g)?.map(Number);
            return values && values.length >= 3 ? values.slice(0, 3) : null;
          };
          const luminance = (values) => {
            const channels = values.map((value) => {
              const normalized = value / 255;
              return normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
            });
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
          };
          const contrast = (a, b) => {
            const x = luminance(a), y = luminance(b);
            return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
          };
          const lowContrast = [];
          for (const el of document.querySelectorAll("body *")) {
            if (!visible(el) || el.children.length || !(el.innerText || "").trim()) continue;
            const textColor = rgb(getComputedStyle(el).color);
            let background = null, ancestor = el;
            while (ancestor && !background) {
              const style = getComputedStyle(ancestor);
              const value = rgb(style.backgroundColor);
              if (value && !style.backgroundColor.endsWith(", 0)") && !style.backgroundColor.endsWith(",0)")) background = value;
              ancestor = ancestor.parentElement;
            }
            if (!textColor || !background) continue;
            const ratio = contrast(textColor, background);
            const style = getComputedStyle(el);
            const large = parseFloat(style.fontSize) >= 18.66 || (Number(style.fontWeight) >= 700 && parseFloat(style.fontSize) >= 14);
            if (ratio < (large ? 3 : 4.5)) lowContrast.push({
              text: (el.innerText || "").trim().slice(0, 80), ratio: Math.round(ratio * 100) / 100,
              fontSize: style.fontSize, color: style.color, background: style.backgroundColor
            });
          }
          const bodyText = document.body.innerText || "";
          const branding = [...bodyText.matchAll(/translation missing[^\\n]*|\\bMaybe\\b|\\bSure\\b/gi)]
            .map((match) => match[0]).filter((text) => !(location.pathname === "/settings/about" && /\\bSure\\b/i.test(text)));
          const box = (el) => {
            const rect = el.getBoundingClientRect();
            return { width: Math.round(rect.width * 10) / 10, height: Math.round(rect.height * 10) / 10,
              left: Math.round(rect.left * 10) / 10, right: Math.round(rect.right * 10) / 10 };
          };
          const compareClasses = (el, classes) => {
            if (!el) return null;
            const after = box(el);
            classes.forEach((name) => el.classList.remove(name));
            const before = box(el);
            classes.forEach((name) => el.classList.add(name));
            return { before, after };
          };
          const mobileTargetComparisons = {};
          const calculator = document.querySelector("[data-money-field-operator-param='+']");
          if (calculator) mobileTargetComparisons.calculatorPlus = compareClasses(calculator, ["max-lg:min-w-11"]);
          const allChip = document.querySelector("[data-providers-filter-target='chip'][data-kind='all']");
          if (allChip) mobileTargetComparisons.bankSyncAll = compareClasses(allChip, ["max-lg:min-w-11"]);
          const segments = [...document.querySelectorAll(".segmented-control__segment")];
          if (segments.length && location.pathname === "/reports") {
            const container = segments[0].parentElement;
            const after = { segmentBoxes: segments.map(box), scrollWidth: container.scrollWidth, clientWidth: container.clientWidth };
            segments.forEach((el) => el.classList.remove("max-lg:shrink-0"));
            const before = { segmentBoxes: segments.map(box), scrollWidth: container.scrollWidth, clientWidth: container.clientWidth };
            segments.forEach((el) => el.classList.add("max-lg:shrink-0"));
            mobileTargetComparisons.reportSegments = { before, after };
          }
          return {
            url: location.pathname + location.search, viewport: { width: innerWidth, height: innerHeight },
            documentOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
            mainOverflow: main ? delta(main) : 0,             dialogOverflow: dialog ? delta(dialog) : 0, dialogOpen: !!document.querySelector("dialog[open]"),
            scrollContainerCount: scrollContainersAll.length, scrollContainers: scrollContainersAll.slice(0, 100),
            controls, clippedCount: clippedAll.length, clipped: clippedAll.slice(0, 100),
            consoleErrors: window.__uiWalk?.consoleErrors || [],
            cspViolations: window.__uiWalk?.cspViolations || [], branding,
            lowContrastCount: lowContrast.length, lowContrast: lowContrast.slice(0, 100), mobileTargetComparisons
          };
        })()
      JS
      browser_errors = read_browser_errors
      row = {
        route: name, width: width, theme: theme, layout: embedded ? "embedded" : "plain", side: side,
        metrics: result, browserErrors: browser_errors
      }
      @measurements << row
    rescue StandardError => error
      record_error(name, width, theme, embedded, side, error)
    end

    def install_browser_listeners
      page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: <<~JS)
        (() => {
          window.__uiWalk = { consoleErrors: [], cspViolations: [] };
          const originalError = console.error.bind(console);
          console.error = (...args) => {
            window.__uiWalk.consoleErrors.push(args.map(String).join(" ").slice(0, 500));
            originalError(...args);
          };
          addEventListener("error", (event) => window.__uiWalk.consoleErrors.push(String(event.message || event.error).slice(0, 500)));
          addEventListener("unhandledrejection", (event) => window.__uiWalk.consoleErrors.push(String(event.reason).slice(0, 500)));
          addEventListener("securitypolicyviolation", (event) => window.__uiWalk.cspViolations.push({
            directive: event.violatedDirective, blockedURI: event.blockedURI, source: event.sourceFile
          }));
        })();
      JS
    end

    def read_browser_errors
      page.driver.browser.manage.logs.get(:browser).select { |entry| entry.level == "SEVERE" }.map(&:message)
    rescue StandardError
      []
    end

    def record_error(name, width, theme, embedded, side, error)
      @measurements << {
        route: name, width: width, theme: theme, layout: embedded ? "embedded" : "plain", side: side,
        routeError: "#{error.class}: #{error.message}"
      }
    end

    def write_measurements
      return unless @measurements

      path = Rails.root.join("tmp/ui_walk.json")
      FileUtils.mkdir_p(path.dirname)
      File.write(path, JSON.pretty_generate(@measurements))
    end
end
