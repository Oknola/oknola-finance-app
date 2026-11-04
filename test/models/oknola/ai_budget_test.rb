# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "test_helper"

class OknolaAiBudgetTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "remaining subtracts current UTC month costs and ignores nil and previous month costs" do
    travel_to Time.utc(2026, 11, 4, 12) do
      usage(created_at: Time.utc(2026, 10, 31, 23, 59, 59), estimated_cost: 10)
      usage(created_at: Time.utc(2026, 11, 1), estimated_cost: 1.25)
      usage(created_at: Time.utc(2026, 11, 2), estimated_cost: nil)

      assert_equal BigDecimal("1.75"), Oknola::AiBudget.remaining(@family)
    end
  end

  test "check! passes while under budget and raises at or above the limit" do
    with_env_overrides("OKNOLA_AI_MONTHLY_USD" => "3.00") do
      assert_nil Oknola::AiBudget.check!(@family)

      usage(created_at: Time.current.utc, estimated_cost: 3)
      assert_raises(Oknola::AiBudget::Exceeded) { Oknola::AiBudget.check!(@family) }

      usage(created_at: Time.current.utc, estimated_cost: 0.01)
      assert_raises(Oknola::AiBudget::Exceeded) { Oknola::AiBudget.check!(@family) }
    end
  end

  test "environment override sets the monthly allowance" do
    usage(created_at: Time.current.utc, estimated_cost: 4)

    with_env_overrides("OKNOLA_AI_MONTHLY_USD" => "5.00") do
      assert_equal BigDecimal("1.00"), Oknola::AiBudget.remaining(@family)
      assert_nil Oknola::AiBudget.check!(@family)
    end
  end

  test "check! skips the budget lookup for a nil family" do
    Oknola::AiBudget.expects(:remaining).never

    assert_nil Oknola::AiBudget.check!(nil)
  end

  private

    def usage(created_at:, estimated_cost:)
      @family.llm_usages.create!(
        provider: "anthropic",
        model: "claude-sonnet-4-6",
        operation: "chat",
        prompt_tokens: 1,
        completion_tokens: 1,
        total_tokens: 2,
        estimated_cost: estimated_cost,
        created_at: created_at
      )
    end
end
