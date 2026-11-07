require "test_helper"

class Oknola::ApiTransactionSidesTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    @user = users(:family_admin)
    @account = accounts(:depository)
    @account.update!(oknola_side: "business")
    @entry = create_transaction(account: @account)
    @user.api_keys.active.destroy_all
    @api_key = ApiKey.create!(
      user: @user,
      name: "Transaction sides",
      scopes: [ "read_write" ],
      display_key: "test_sides_#{SecureRandom.hex(8)}"
    )
  end

  %w[business personal].each do |account_side|
    %w[business personal].each do |side|
      test "create #{side} on a #{account_side} account normalizes through the entry" do
        @account.update!(oknola_side: account_side)

        assert_difference "Transaction.count", 1 do
          post api_v1_transactions_url,
            params: { transaction: create_params.merge(oknola_side: side) },
            headers: api_headers, as: :json
        end

        assert_response :created
        transaction = Transaction.find(response.parsed_body["id"])
        if side == account_side
          assert_nil transaction.oknola_side
        else
          assert_equal side, transaction.oknola_side
        end
        assert_equal side, response.parsed_body["oknola_side"]
      end
    end
  end

  test "create without a side inherits the account side" do
    post api_v1_transactions_url,
      params: { transaction: create_params }, headers: api_headers, as: :json

    assert_response :created
    assert_nil Transaction.find(response.parsed_body["id"]).oknola_side
    assert_equal "business", response.parsed_body["oknola_side"]
  end

  test "update sets an override and normalizes the account side" do
    patch_transaction(oknola_side: "personal")
    assert_response :success
    assert_equal "personal", @entry.transaction.reload.oknola_side
    assert_equal "personal", response.parsed_body["oknola_side"]

    patch_transaction(oknola_side: "business")
    assert_response :success
    assert_nil @entry.transaction.reload.oknola_side
    assert_equal "business", response.parsed_body["oknola_side"]
  end

  [ nil, "", " \t" ].each do |blank|
    test "create accepts a blank side #{blank.inspect}" do
      post api_v1_transactions_url,
        params: { transaction: create_params.merge(oknola_side: blank) },
        headers: api_headers, as: :json

      assert_response :created
      assert_nil Transaction.find(response.parsed_body["id"]).oknola_side
      assert_equal "business", response.parsed_body["oknola_side"]
    end

    test "update clears the override with #{blank.inspect}" do
      @entry.transaction.update!(oknola_side: "personal")

      patch_transaction(oknola_side: blank)

      assert_response :success
      assert_nil @entry.transaction.reload.oknola_side
      assert_equal "business", response.parsed_body["oknola_side"]
    end
  end

  test "omitting the side leaves the override unchanged" do
    @entry.transaction.update!(oknola_side: "personal")

    patch_transaction(name: "Renamed")

    assert_response :success
    assert_equal "personal", @entry.transaction.reload.oknola_side
    assert_equal "personal", response.parsed_body["oknola_side"]
  end

  [ "invalid", "Business", false, 1, [], {} ].each do |invalid|
    test "create and update reject invalid side #{invalid.inspect}" do
      assert_no_difference "Transaction.count" do
        post api_v1_transactions_url,
          params: { transaction: create_params.merge(oknola_side: invalid) },
          headers: api_headers, as: :json
      end
      assert_response :unprocessable_entity
      assert_equal "validation_failed", response.parsed_body["error"]

      @entry.transaction.update!(oknola_side: "personal")
      patch_transaction(oknola_side: invalid, name: "Must not change")

      assert_response :unprocessable_entity
      assert_equal "validation_failed", response.parsed_body["error"]
      assert_equal "personal", @entry.transaction.reload.oknola_side
      assert_equal "Transaction", @entry.reload.name
    end
  end

  test "show and index return the effective side" do
    overridden = create_transaction(account: @account)
    overridden.transaction.update!(oknola_side: "personal")

    { @entry => "business", overridden => "personal" }.each do |entry, side|
      get api_v1_transaction_url(entry.transaction), headers: api_headers
      assert_response :success
      assert_equal side, response.parsed_body["oknola_side"]
    end

    get api_v1_transactions_url, params: { account_id: @account.id }, headers: api_headers
    assert_response :success
    sides = response.parsed_body["transactions"].index_by { |row| row["id"] }
    assert_equal "business", sides.fetch(@entry.transaction.id)["oknola_side"]
    assert_equal "personal", sides.fetch(overridden.transaction.id)["oknola_side"]
  end

  test "index preloads accounts when resolving inherited sides" do
    account_queries = []
    callback = ->(*args) do
      payload = args.last
      account_queries << payload[:sql] if payload[:name] == "Account Load"
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get api_v1_transactions_url, params: { per_page: 100 }, headers: api_headers
    end
    assert_response :success
    baseline_queries = account_queries.size
    account_queries.clear

    5.times do
      account = @user.family.accounts.create!(
        name: "Business account", balance: 0, currency: "USD",
        accountable: Depository.new, oknola_side: "business"
      )
      create_transaction(account: account)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get api_v1_transactions_url, params: { per_page: 100 }, headers: api_headers
    end

    assert_response :success
    assert_equal baseline_queries, account_queries.size
  end

  test "a side update still refuses split children" do
    @entry.split!([ { name: "Child", amount: @entry.amount } ])
    child = @entry.child_entries.sole

    patch api_v1_transaction_url(child.transaction),
      params: { transaction: { oknola_side: "personal" } }, headers: api_headers, as: :json

    assert_response :unprocessable_entity
    assert_equal "validation_failed", response.parsed_body["error"]
    assert_nil child.transaction.reload.oknola_side
  end

  %w[read_only read_write full_control].each do |permission|
    test "#{permission} account share respects side write permissions" do
      member = users(:family_member)
      account_shares(:depository_shared_with_member).update!(permission: permission)
      member.api_keys.active.destroy_all
      @api_key = ApiKey.create!(
        user: member, name: "Shared account sides", scopes: [ "read_write" ],
        display_key: "test_shared_sides_#{SecureRandom.hex(8)}"
      )

      get api_v1_transaction_url(@entry.transaction), headers: api_headers
      assert_response :success
      assert_equal "business", response.parsed_body["oknola_side"]

      [ "personal", nil, "" ].each do |side|
        @entry.transaction.update!(oknola_side: "personal")
        patch_transaction(oknola_side: side)

        if permission == "full_control" || (permission == "read_write" && side == "personal")
          assert_response :success
          if side == "personal"
            assert_equal side, @entry.transaction.reload.oknola_side
          else
            assert_nil @entry.transaction.reload.oknola_side
          end
        else
          assert_response :forbidden
          assert_equal "forbidden", response.parsed_body["error"]
          assert_equal "personal", @entry.transaction.reload.oknola_side
        end
      end
    end
  end

  test "read-only API keys cannot write a side" do
    @api_key.update!(scopes: [ "read" ])

    post api_v1_transactions_url,
      params: { transaction: create_params.merge(oknola_side: "personal") },
      headers: api_headers, as: :json
    assert_response :forbidden

    patch_transaction(oknola_side: "personal")
    assert_response :forbidden
    assert_nil @entry.transaction.reload.oknola_side
  end

  private

    def api_headers
      { "X-Api-Key" => @api_key.display_key }
    end

    def create_params
      { account_id: @account.id, name: "API transaction", date: Date.current.to_s, amount: 10 }
    end

    def patch_transaction(attributes)
      patch api_v1_transaction_url(@entry.transaction),
        params: { transaction: attributes }, headers: api_headers, as: :json
    end
end
