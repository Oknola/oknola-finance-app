require "test_helper"

class AccountsControllerOknolaTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @family.tags.create!(name: "Business")
    @family.tags.create!(name: "Personal")
  end

  test "account side is created, rendered, and removed through the account form" do
    assert_difference "Rule.count", 1 do
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
    rule = Oknola::AccountSide.rule_for(account)
    assert_equal "business", Oknola::AccountSide.side_for(account)

    get edit_depository_path(account)

    assert_response :success
    assert_select "select[name='account[side]'] option[selected][value='business']"

    assert_difference "Rule.count", -1 do
      patch depository_path(account), params: { account: { side: "mixed" } }
    end

    assert_nil Oknola::AccountSide.rule_for(account)
    assert_not_nil rule
  end

  test "account side is unchanged when the form omits it" do
    account = accounts(:depository)
    Oknola::AccountSide.set(account, "personal")
    rule = Oknola::AccountSide.rule_for(account)

    patch depository_path(account), params: { account: { name: "Renamed Checking" } }

    assert_response :redirect
    assert_equal rule.id, Oknola::AccountSide.rule_for(account).id
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
  end
end
