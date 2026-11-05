# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "test_helper"

class Oknola::QuickEntryTest < ActiveSupport::TestCase
  test "account sides map each account to its default side" do
    business = accounts(:depository)
    personal = accounts(:credit_card)
    business.update!(oknola_side: "business")

    assert_equal(
      { business.id => "business", personal.id => "personal" },
      Oknola::QuickEntry.account_sides([ business, personal ])
    )
  end
end
