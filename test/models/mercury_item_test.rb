# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "test_helper"

class MercuryItemTest < ActiveSupport::TestCase
  def setup
    @mercury_item = mercury_items(:one)
  end

  test "fixture is valid" do
    assert @mercury_item.valid?
  end

  test "belongs to family" do
    assert_equal families(:dylan_family), @mercury_item.family
  end

  test "credentials_configured returns true when token present" do
    assert @mercury_item.credentials_configured?
  end

  test "credentials_configured returns false when token blank" do
    @mercury_item.token = nil
    assert_not @mercury_item.credentials_configured?
  end

  test "credentials_configured returns false when token is whitespace" do
    @mercury_item.token = "   "
    assert_not @mercury_item.credentials_configured?
  end

  test "effective_base_url returns custom url when set" do
    assert_equal "https://api-sandbox.mercury.com/api/v1", @mercury_item.effective_base_url
  end

  test "effective_base_url returns default when base_url blank" do
    @mercury_item.base_url = nil
    assert_equal "https://api.mercury.com/api/v1", @mercury_item.effective_base_url
  end

  test "base_url accepts only Mercury production and sandbox origins" do
    {
      "https://api.mercury.com" => "https://api.mercury.com/api/v1",
      "https://api-sandbox.mercury.com/api/v1/" => "https://api-sandbox.mercury.com/api/v1"
    }.each do |base_url, expected|
      item = MercuryItem.new(family: families(:empty), name: "Allowed Mercury", token: "token", base_url: base_url)

      assert item.valid?, "#{base_url.inspect} should be valid"
      assert_equal expected, item.effective_base_url
    end
  end

  test "base_url rejects non-Mercury origins and unsafe URL components" do
    [
      "http://api.mercury.com/api/v1",
      "https://169.254.169.254",
      "https://127.0.0.1",
      "https://localhost",
      "https://10.0.0.1",
      "https://api.mercury.com.evil.example",
      "https://evil.example/api.mercury.com",
      "https://user@api.mercury.com",
      "https://api.mercury.com:444",
      "https://api.mercury.com/api/v1?query=1",
      "https://api.mercury.com/api/v1#fragment"
    ].each do |base_url|
      item = MercuryItem.new(family: families(:empty), name: "Invalid Mercury", token: "token", base_url: base_url)

      refute item.valid?, "Expected #{base_url.inspect} to be invalid"
      assert_includes item.errors.details[:base_url].map { |error| error[:error] }, :invalid
    end
  end

  test "legacy disallowed base_url is never requested" do
    bad_url = "https://169.254.169.254"
    @mercury_item.update_column(:base_url, bad_url)
    stub_request(:get, "https://api.mercury.com/api/v1/account/account-1/transactions")
      .to_return(status: 200, body: { transactions: [] }.to_json)

    @mercury_item.reload.mercury_provider.get_account_transactions("account-1")

    assert_requested(:get, "https://api.mercury.com/api/v1/account/account-1/transactions")
    assert_not_requested(:get, bad_url)
  end

  test "mercury_provider returns Provider::Mercury instance" do
    provider = @mercury_item.mercury_provider
    assert_instance_of Provider::Mercury, provider
    assert_equal @mercury_item.token, provider.token
  end

  test "mercury_provider returns nil when credentials not configured" do
    @mercury_item.token = nil
    assert_nil @mercury_item.mercury_provider
  end

  test "family credential check ignores blank and scheduled for deletion items" do
    family = families(:empty)
    blank_item = MercuryItem.create!(
      family: family,
      name: "Blank Mercury",
      token: "temporary_token",
      base_url: "https://api-sandbox.mercury.com/api/v1"
    )
    blank_item.update_column(:token, "")

    whitespace_item = MercuryItem.create!(
      family: family,
      name: "Whitespace Mercury",
      token: "temporary_token",
      base_url: "https://api-sandbox.mercury.com/api/v1"
    )
    whitespace_item.update_column(:token, "   ")

    deleted_item = MercuryItem.create!(
      family: family,
      name: "Deleted Mercury",
      token: "deleted_token",
      base_url: "https://api-sandbox.mercury.com/api/v1",
      scheduled_for_deletion: true
    )

    refute family.has_mercury_credentials?

    whitespace_item.update_column(:token, "configured_token")
    assert family.has_mercury_credentials?

    whitespace_item.update_column(:token, "   ")
    deleted_item.update!(scheduled_for_deletion: false)
    assert family.has_mercury_credentials?
  end

  test "syncer returns MercuryItem::Syncer instance" do
    syncer = @mercury_item.send(:syncer)
    assert_instance_of MercuryItem::Syncer, syncer
  end
end
