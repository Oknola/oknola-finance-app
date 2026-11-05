# frozen_string_literal: true

# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
require "test_helper"

class Api::V1::BalanceSheetControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family

    @user.api_keys.active.destroy_all

    @auth = ApiKey.create!(
      user: @user,
      name: "Test Read Key",
      scopes: [ "read" ],
      display_key: "test_ro_#{SecureRandom.hex(8)}",
      source: "mobile"
    )

    Redis.new.del("api_rate_limit:#{@auth.id}")
  end

  test "should require authentication" do
    get "/api/v1/balance_sheet"
    assert_response :unauthorized
  end

  test "should return balance sheet with net worth data" do
    get "/api/v1/balance_sheet", headers: api_headers(@auth)

    assert_response :success
    response_body = JSON.parse(response.body)

    assert response_body.key?("currency")
    assert response_body.key?("net_worth")
    assert response_body.key?("assets")
    assert response_body.key?("liabilities")

    %w[net_worth assets liabilities].each do |field|
      assert response_body[field].key?("amount"), "#{field} should have amount"
      assert response_body[field].key?("currency"), "#{field} should have currency"
      assert response_body[field].key?("formatted"), "#{field} should have formatted"
    end
  end

  test "API balance sheet totals include both sides despite the saved browser side" do
    @user.update!(preferences: (@user.preferences || {}).merge("oknola_side" => "business"))
    get "/api/v1/balance_sheet", headers: api_headers(@auth)
    before_assets = response.parsed_body.dig("assets", "amount").to_d

    @family.accounts.create!(
      name: "Business",
      owner: @user,
      currency: "USD",
      balance: 100,
      accountable: Depository.new,
      oknola_side: "business"
    )
    @family.accounts.create!(
      name: "Personal",
      owner: @user,
      currency: "USD",
      balance: 200,
      accountable: Depository.new,
      oknola_side: "personal"
    )

    get "/api/v1/balance_sheet", headers: api_headers(@auth)

    assert_response :success
    assert_equal before_assets + 300, response.parsed_body.dig("assets", "amount").to_d
  end

  private

    def api_headers(auth)
      { "X-Api-Key" => auth.display_key }
    end
end
