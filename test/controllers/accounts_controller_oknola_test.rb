# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "test_helper"

class AccountsControllerOknolaTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @family.tags.create!(name: "Business")
    @family.tags.create!(name: "Personal")
  end

  test "account side is created and rendered through the account form" do
    assert_no_difference "Rule.count" do
      post depositories_path, params: {
        account: {
          name: "Business Checking",
          currency: "USD",
          balance: 100,
          accountable_type: "Depository",
          side: "business"
        }
      }
    end
    account = @family.accounts.find_by!(name: "Business Checking")
    assert_equal "business", Oknola::AccountSide.side_for(account)

    get edit_depository_path(account)

    assert_response :success
    assert_select "select[name='account[side]'] option[selected][value='business']"
    assert_select "select[name='account[side]'] option[value='mixed']", count: 0
    assert_includes response.body, "Default for this account&#39;s transactions. You can change any transaction."

    patch depository_path(account), params: { account: { side: "personal" } }

    assert_equal "personal", account.reload.oknola_side
  end

  test "account side is unchanged when the form omits it" do
    account = accounts(:depository)
    Oknola::AccountSide.set(account, "personal")

    patch depository_path(account), params: { account: { name: "Renamed Checking" } }

    assert_response :redirect
    assert_equal "personal", Oknola::AccountSide.side_for(account)
  end

  test "creating an account without a side does not create a rule" do
    assert_no_difference "Rule.count" do
      post depositories_path, params: {
        account: {
          name: "Mixed Checking",
          currency: "USD",
          balance: 100,
          accountable_type: "Depository"
        }
      }
    end
    assert_equal "personal", @family.accounts.find_by!(name: "Mixed Checking").oknola_side
  end
end
