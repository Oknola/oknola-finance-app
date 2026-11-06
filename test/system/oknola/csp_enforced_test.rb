# Modified by Cardona Labs, LLC, 2026-11-06, AGPL-3.0
require "application_system_test_case"
require "timeout"

class Oknola::CspEnforcedTest < ApplicationSystemTestCase
  test "enforces CSP across primary pages and reports blocked inline scripts" do
    report_count = 0
    report_mutex = Mutex.new
    subscriber = ActiveSupport::Notifications.subscribe("process_action.action_controller") do |_name, _start, _finish, _id, payload|
      next unless payload[:controller] == "Oknola::CspReportsController"

      report_mutex.synchronize { report_count += 1 }
    end

    sign_in users(:family_admin)

    [
      "/",
      "/transactions",
      "/reports",
      "/budgets",
      "/accounts",
      "/imports/new",
      "/settings/providers",
      "/settings/preferences",
      "/settings/appearance",
      "/rules",
      "/categories",
      "/tags"
    ].each { |path| visit path }

    sleep 0.25
    assert_equal 0, report_mutex.synchronize { report_count }

    page.execute_script(<<~JS)
      const script = document.createElement("script");
      script.textContent = "window.__oknolaCspViolationScriptRan = true";
      document.body.append(script);
    JS

    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.05 until report_mutex.synchronize { report_count.positive? }
    end

    assert_equal 1, report_mutex.synchronize { report_count }
    assert_nil page.evaluate_script("window.__oknolaCspViolationScriptRan")
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
