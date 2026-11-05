# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
require "application_system_test_case"

class SignInAccessibilityTest < ApplicationSystemTestCase
  test "sign-in page has accessible branding, zoom, and placeholder contrast" do
    visit new_session_path

    logo = find("img")
    assert logo["alt"].present?, "sign-in logo needs non-empty alt text"
    assert_equal "width=device-width, initial-scale=1, viewport-fit=cover",
      page.evaluate_script("document.querySelector('meta[name=\"viewport\"]').content")

    email_input = find("input[type='email']")
    assert_placeholder_contrast(email_input, "light")

    page.execute_script("document.documentElement.setAttribute('data-theme', 'dark')")
    assert_placeholder_contrast(email_input, "dark")
  end

  private

    def assert_placeholder_contrast(input, theme)
      styles = input.evaluate_script(<<~JS)
        ({
          color: getComputedStyle(this, "::placeholder").color,
          background: getComputedStyle(this).backgroundColor,
          opacity: getComputedStyle(this).opacity
        })
      JS

      assert_equal "1", styles.fetch("opacity"), "#{theme} input opacity"
      assert_operator contrast_ratio(styles.fetch("color"), styles.fetch("background")),
        :>=, 4.5, "#{theme} placeholder contrast"
    end

    def contrast_ratio(foreground, background)
      colors = [ foreground, background ].map do |color|
        channels = color.match(/rgba?\(([^)]+)\)/).captures.first.scan(/[0-9.]+/).map(&:to_f)
        channels.first(3).map { |channel| channel / 255.0 }
      end

      luminances = colors.map do |channels|
        channels.map { |channel| channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055)**2.4 }
          .zip([ 0.2126, 0.7152, 0.0722 ])
          .sum { |channel, weight| channel * weight }
      end

      lighter, darker = luminances.max, luminances.min
      (lighter + 0.05) / (darker + 0.05)
    end
end
