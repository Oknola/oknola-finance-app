# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "test_helper"

class Oknola::AccountSideTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @account = accounts(:depository)
    @business_entry = create_transaction(account: @account)
    @business_entry.transaction.update!(oknola_side: "business")
    @personal_entry = create_transaction(account: @account)
    @personal_entry.transaction.update!(oknola_side: "personal")
  end

  test "setting the default side clears overrides that now match it" do
    assert_equal "business", Oknola::AccountSide.set(@account, "business")

    @account.reload
    @business_entry.reload
    @personal_entry.reload
    assert_equal "business", @account.oknola_side
    assert_nil @business_entry.transaction.oknola_side
    assert_equal "personal", @personal_entry.transaction.oknola_side

    @business_entry.transaction.update!(oknola_side: "business")
    assert_equal "personal", Oknola::AccountSide.set(@account, "personal")

    @account.reload
    @business_entry.reload
    @personal_entry.reload
    assert_equal "personal", @account.oknola_side
    assert_equal "business", @business_entry.transaction.oknola_side
    assert_nil @personal_entry.transaction.oknola_side
    assert_equal "personal", Oknola::AccountSide.side_for(@account)
  end

  test "unsupported sides do not change the default" do
    assert_equal false, Oknola::AccountSide.set(@account, "mixed")
    assert_equal "personal", @account.reload.oknola_side
  end
end
