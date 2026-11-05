# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
require "test_helper"

class Insight::Generators::BudgetInsightGeneratorTest < ActiveSupport::TestCase
  test "uses the Personal budget when both sides exist for the current month" do
    family = families(:empty)
    start_date = Date.current.beginning_of_month
    end_date = Date.current.end_of_month
    business = family.budgets.create!(
      id: "00000000-0000-0000-0000-000000000001",
      start_date: start_date,
      end_date: end_date,
      currency: family.currency,
      oknola_side: "business"
    )
    personal = family.budgets.create!(
      id: "ffffffff-ffff-ffff-ffff-ffffffffffff",
      start_date: start_date,
      end_date: end_date,
      currency: family.currency,
      oknola_side: "personal"
    )

    generator = Insight::Generators::BudgetInsightGenerator.new(family)

    assert_equal personal, generator.send(:current_budget)
    refute_equal business, generator.send(:current_budget)
  end
end
