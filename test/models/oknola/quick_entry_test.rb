require "test_helper"

class Oknola::QuickEntryTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @business = @family.tags.create!(name: "Business")
    @personal = @family.tags.create!(name: "Personal")
  end

  test "side tags use exact names within the family" do
    assert_equal({ "business" => @business.id, "personal" => @personal.id }, Oknola::QuickEntry.side_tags(@family))
    assert_empty Oknola::QuickEntry.side_tags(families(:empty))
  end

  test "both side tags are required" do
    @personal.destroy!
    @family.tags.create!(name: "personal")

    assert_empty Oknola::QuickEntry.side_tags(@family)
  end

  test "account sides map business and personal tags and leave mixed accounts unset" do
    business = accounts(:depository)
    personal = accounts(:credit_card)
    mixed = accounts(:other_asset)
    Oknola::AccountSide.set(business, "business")
    Oknola::AccountSide.set(personal, "personal")

    assert_equal(
      { business.id => @business.id, personal.id => @personal.id, mixed.id => nil },
      Oknola::QuickEntry.account_sides(@family, [ business, personal, mixed ])
    )
  end

  test "account sides skip classification when a side tag is missing" do
    account = accounts(:depository)
    Oknola::AccountSide.set(account, "business")
    @personal.destroy!

    Oknola::AccountSide.expects(:side_for).never

    assert_empty Oknola::QuickEntry.account_sides(@family, [ account ])
  end

  test "account sides skip enumerating accounts when no side tags exist" do
    @business.destroy!
    @personal.destroy!
    accounts = mock
    accounts.expects(:to_h).never
    Oknola::AccountSide.expects(:side_for).never

    assert_empty Oknola::QuickEntry.account_sides(@family, accounts)
  end
end
