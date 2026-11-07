# Modified by Cardona Labs, LLC, 2026-11-07, AGPL-3.0
require "test_helper"

class DS::ButtonTest < ViewComponent::TestCase
  test "text buttons meet the mobile target height" do
    render_inline(DS::Button.new(text: "Save"))

    assert_selector "button[class*='max-lg:min-h-11']"
  end

  test "icon buttons meet the mobile target size" do
    render_inline(DS::Button.new(variant: :icon, size: :sm, icon: "x"))

    assert_selector "button[class*='max-lg:min-w-11'][class*='max-lg:min-h-11']"
  end
end
