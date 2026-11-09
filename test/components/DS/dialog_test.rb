# Modified by Cardona Labs, LLC, 2026-11-07, AGPL-3.0
require "test_helper"

class DS::DialogTest < ViewComponent::TestCase
  # Turbo caches a page as it was left, and Back restores that copy. A drawer or
  # modal fetched into the page came back with it: stray and non-modal if it was
  # still open, opened again if it had been closed.
  test "a drawer fetched into its frame is left out of Turbo's page cache" do
    vc_test_request.headers["Turbo-Frame"] = "drawer"
    render_inline(DS::Dialog.new(frame: "drawer", responsive: true))

    assert_selector "turbo-frame#drawer > dialog[data-turbo-temporary]"
  end

  test "a drawer fetched into a frame of its own is left out of Turbo's page cache" do
    vc_test_request.headers["Turbo-Frame"] = "bulk_transaction_edit_drawer"
    render_inline(DS::Dialog.new(variant: "drawer", frame: "bulk_transaction_edit_drawer"))

    assert_selector "turbo-frame#bulk_transaction_edit_drawer > dialog[data-turbo-temporary]"
  end

  # Visited directly, the drawer is the page, and Back has to bring it back.
  test "a drawer rendered as the page stays in the cache" do
    render_inline(DS::Dialog.new(frame: "drawer", responsive: true))

    assert_selector "turbo-frame#drawer > dialog"
    assert_no_selector "dialog[data-turbo-temporary]"
  end

  # Transaction, trade and other detail drawers put this button in their
  # custom headers and have no other way out on a phone.
  test "a responsive dialog's close button shows and meets the mobile target size" do
    dialog = DS::Dialog.new(frame: "drawer", responsive: true)
    render_inline(dialog) do
      dialog.with_header(custom_header: true) { dialog.close_button }
    end

    close = page.find("button[data-action='DS--dialog#close']")
    refute_includes close[:class].split, "hidden"
    assert_includes close[:class].split, "max-lg:min-h-11"
    assert_includes close[:class].split, "max-lg:min-w-11"
  end

  test "a modal fetched into the modal frame is left out of Turbo's page cache" do
    vc_test_request.headers["Turbo-Frame"] = "modal"
    render_inline(DS::Dialog.new)

    assert_selector "turbo-frame#modal > dialog[data-turbo-temporary]"
  end
end
