# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
require "test_helper"

class DS::SegmentedControlTest < ViewComponent::TestCase
  test "renders segments as buttons by default with the base + active classes" do
    render_inline(DS::SegmentedControl.new) do |sc|
      sc.with_segment("All", active: true)
      sc.with_segment("Over Budget")
    end

    assert_selector "div.segmented-control[role=group]"
    assert_selector "button.segmented-control__segment", count: 2
    assert_selector "button.segmented-control__segment[class*='max-lg:min-w-11'][class*='max-lg:min-h-11']", count: 2
    assert_selector "button.segmented-control__segment--active", text: "All", count: 1
    refute_selector "button.segmented-control__segment--active", text: "Over Budget"
  end

  test "href renders a segment as a link" do
    render_inline(DS::SegmentedControl.new) do |sc|
      sc.with_segment("Sign in", href: "/login", active: true)
      sc.with_segment("Sign up", href: "/join")
    end

    assert_selector "a.segmented-control__segment--active[href='/login']", text: "Sign in"
    assert_selector "a.segmented-control__segment[href='/join']", text: "Sign up"
  end

  test "form_action renders a PATCH button segment with current state" do
    render_inline(DS::SegmentedControl.new(aria_label: "Side")) do |sc|
      sc.with_segment("Business", active: true, form_action: "/side", form_params: { side: "business" })
      sc.with_segment("Personal", form_action: "/side", form_params: { side: "personal" })
    end

    assert_selector "form.contents[action='/side'] input[name='_method'][value='patch']", count: 2, visible: false
    assert_selector "form.contents button.segmented-control__segment[aria-current='true']", text: "Business"
    assert_selector "form.contents button.segmented-control__segment:not([aria-current])", text: "Personal"
    assert_selector "form.contents input[name='side'][value='business']", visible: false
    assert_selector "form.contents input[name='side'][value='personal']", visible: false
  end

  test "full_width stretches the track and each segment" do
    render_inline(DS::SegmentedControl.new(full_width: true)) do |sc|
      sc.with_segment("One", active: true)
      sc.with_segment("Two")
    end

    assert_selector "div.segmented-control.w-full"
    assert_selector "button.segmented-control__segment.flex-1", count: 2
  end

  test "aria_label and passthrough attrs land on the wrapper" do
    render_inline(DS::SegmentedControl.new(aria_label: "Filter", data: { controller: "x" })) do |sc|
      sc.with_segment("A", active: true)
    end

    assert_selector "div.segmented-control[aria-label='Filter'][data-controller='x']"
  end

  test "per-segment passthrough class and data merge onto the segment" do
    render_inline(DS::SegmentedControl.new) do |sc|
      sc.with_segment("A", active: true, class: "custom-x", data: { id: "a" })
    end

    assert_selector "button.segmented-control__segment--active.custom-x[data-id='a']"
  end
end
