# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "test_helper"

class LunchflowItemTest < ActiveSupport::TestCase
  def setup
    @lunchflow_item = lunchflow_items(:one)
  end

  test "effective_base_url returns default when base_url blank" do
    @lunchflow_item.base_url = nil

    assert_equal LunchflowItem::DEFAULT_BASE_URL, @lunchflow_item.effective_base_url
  end

  test "effective_base_url returns default for non-lunchflow host" do
    @lunchflow_item.base_url = "https://169.254.169.254/latest/meta-data"

    assert_equal LunchflowItem::DEFAULT_BASE_URL, @lunchflow_item.effective_base_url
  end

  test "effective_base_url returns default for non-https scheme" do
    @lunchflow_item.base_url = "http://lunchflow.app/api/v1"

    assert_equal LunchflowItem::DEFAULT_BASE_URL, @lunchflow_item.effective_base_url
  end

  test "effective_base_url returns canonical default for valid lunchflow url" do
    @lunchflow_item.base_url = "https://lunchflow.app/api/v1/"

    assert_equal LunchflowItem::DEFAULT_BASE_URL, @lunchflow_item.effective_base_url
  end

  test "base_url accepts only the Lunchflow production origin" do
    [ "https://lunchflow.app", "https://lunchflow.app/api/v1/" ].each do |base_url|
      item = LunchflowItem.new(family: families(:empty), name: "Allowed Lunchflow", api_key: "key", base_url: base_url)

      assert item.valid?, "#{base_url.inspect} should be valid"
      assert_equal LunchflowItem::DEFAULT_BASE_URL, item.effective_base_url
    end
  end

  test "base_url rejects non-Lunchflow origins and unsafe URL components" do
    [
      "http://lunchflow.app/api/v1",
      "https://169.254.169.254",
      "https://127.0.0.1",
      "https://localhost",
      "https://10.0.0.1",
      "https://lunchflow.app.evil.example",
      "https://evil.example/lunchflow.app",
      "https://user@lunchflow.app",
      "https://lunchflow.app:444",
      "https://lunchflow.app/api/v1?query=1",
      "https://lunchflow.app/api/v1#fragment"
    ].each do |base_url|
      item = LunchflowItem.new(family: families(:empty), name: "Invalid Lunchflow", api_key: "key", base_url: base_url)

      refute item.valid?, "Expected #{base_url.inspect} to be invalid"
      assert_includes item.errors.details[:base_url].map { |error| error[:error] }, :invalid
    end
  end

  test "legacy disallowed base_url is never requested" do
    bad_url = "https://169.254.169.254"
    @lunchflow_item.update_column(:base_url, bad_url)
    stub_request(:get, "#{LunchflowItem::DEFAULT_BASE_URL}/accounts")
      .to_return(status: 200, body: { accounts: [] }.to_json)

    @lunchflow_item.reload.lunchflow_provider.get_accounts

    assert_requested(:get, "#{LunchflowItem::DEFAULT_BASE_URL}/accounts")
    assert_not_requested(:get, bad_url)
  end

  test "sync status summary covers every German count branch" do
    assert_sync_status(:de, total: 0, linked: 0, unlinked: 0, expected: "Keine Konten gefunden")
    assert_sync_status(:de, total: 1, linked: 1, unlinked: 0, expected: "1 Konto synchronisiert")
    assert_sync_status(:de, total: 2, linked: 2, unlinked: 0, expected: "2 Konten synchronisiert")
    assert_sync_status(:de, total: 2, linked: 1, unlinked: 1, expected: "1 synchronisiert, 1 muss eingerichtet werden")
    assert_sync_status(:de, total: 3, linked: 1, unlinked: 2, expected: "1 synchronisiert, 2 müssen eingerichtet werden")
  end

  test "sync status summary covers every English count branch" do
    assert_sync_status(:en, total: 0, linked: 0, unlinked: 0, expected: "No accounts found")
    assert_sync_status(:en, total: 1, linked: 1, unlinked: 0, expected: "1 account synced")
    assert_sync_status(:en, total: 2, linked: 2, unlinked: 0, expected: "2 accounts synced")
    assert_sync_status(:en, total: 2, linked: 1, unlinked: 1, expected: "1 synced, 1 needs setup")
    assert_sync_status(:en, total: 3, linked: 1, unlinked: 2, expected: "1 synced, 2 need setup")
  end

  private
    def assert_sync_status(locale, total:, linked:, unlinked:, expected:)
      @lunchflow_item.stubs(:total_accounts_count).returns(total)
      @lunchflow_item.stubs(:linked_accounts_count).returns(linked)
      @lunchflow_item.stubs(:unlinked_accounts_count).returns(unlinked)

      I18n.with_locale(locale) do
        assert_equal expected, @lunchflow_item.sync_status_summary
      end
    end
end
