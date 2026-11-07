require "test_helper"

class Oknola::AutoSyncIsolationTest < ActionDispatch::IntegrationTest
  test "fixture families do not auto-sync after midnight unless enabled" do
    sign_in users(:family_admin)

    travel_to Date.tomorrow.beginning_of_day + 1.minute do
      Family.any_instance.expects(:sync_later).never
      get root_path
      assert_response :success
    end
  end

  test "auto-sync can be enabled explicitly" do
    family = families(:dylan_family)
    family.update!(auto_sync_on_login: true)
    sign_in users(:family_admin)

    travel_to Date.tomorrow.beginning_of_day + 1.minute do
      Family.any_instance.expects(:request_plaid_transactions_refreshes_later).with(source: "AutoSync")
      Family.any_instance.expects(:sync_later)
      get root_path
      assert_response :success
    end
  end
end
