# Modified by Cardona Labs, LLC, 2026-11-07, AGPL-3.0
require "test_helper"

class DS::MenuTest < ViewComponent::TestCase
  test "custom menu buttons meet the mobile target height" do
    render_inline(DS::Menu.new(variant: :button)) do |menu|
      menu.with_button(aria: { label: "Select month" }) { "November 2026" }
    end

    assert_selector "button[data-ds--menu-target='button'][class*='max-lg:min-h-11']"
  end
end
