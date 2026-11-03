require "test_helper"

class Oknola::AccountSideTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @other_account = accounts(:credit_card)
    @business_tag = @family.tags.create!(name: "Business")
    @personal_tag = @family.tags.create!(name: "Personal")
    @transaction = create_transaction(account: @account).transaction
  end

  test "business creates one rule and tags existing transactions" do
    assert_difference "Rule.count", 1 do
      perform_enqueued_jobs { Oknola::AccountSide.set(@account, "business") }
    end

    rule = Oknola::AccountSide.rule_for(@account)
    assert_equal 1, rule.conditions.count
    assert_equal 1, rule.actions.count
    assert_includes @transaction.reload.tags, @business_tag
    assert_equal "business", Oknola::AccountSide.side_for(@account)
  end

  test "business creates a rule and enqueues its application" do
    assert_enqueued_with(job: RuleJob) do
      Oknola::AccountSide.set(@account, "business")
    end

    assert Oknola::AccountSide.rule_for(@account)
  end

  test "personal updates the same rule and replaces the other side tag" do
    perform_enqueued_jobs { Oknola::AccountSide.set(@account, "business") }
    assert_includes @transaction.reload.tags, @business_tag
    rule = Oknola::AccountSide.rule_for(@account)
    assert_no_difference "Rule.count" do
      perform_enqueued_jobs { Oknola::AccountSide.set(@account, "personal") }
    end

    assert_equal rule.id, Oknola::AccountSide.rule_for(@account).id
    assert_equal "personal", Oknola::AccountSide.side_for(@account)
    assert_includes @transaction.reload.tags, @personal_tag
    assert_not_includes @transaction.tags, @business_tag
  end

  test "mixed removes the rule and leaves existing tags alone" do
    perform_enqueued_jobs { Oknola::AccountSide.set(@account, "business") }
    tags_before = @transaction.reload.tags.to_a

    assert_difference "Rule.count", -1 do
      Oknola::AccountSide.set(@account, "mixed")
    end

    assert_nil Oknola::AccountSide.rule_for(@account)
    assert_equal tags_before, @transaction.reload.tags.to_a
    assert_equal "mixed", Oknola::AccountSide.side_for(@account)
  end

  test "setting a side leaves another account's rule untouched" do
    Oknola::AccountSide.set(@other_account, "personal")
    other_rule = Oknola::AccountSide.rule_for(@other_account)

    Oknola::AccountSide.set(@account, "business")

    assert_equal other_rule.attributes, Oknola::AccountSide.rule_for(@other_account).attributes
    assert_equal @other_account.id.to_s, other_rule.conditions.first.value
  end

  test "setting a side is a no-op when the family tags are unavailable" do
    @personal_tag.destroy!

    assert_no_difference "Rule.count" do
      assert_equal "business", Oknola::AccountSide.set(@account, "business")
    end

    assert_nil Oknola::AccountSide.rule_for(@account)
  end

  test "a new transaction receives the side tag on the next rules run" do
    Oknola::AccountSide.set(@account, "business")
    transaction = create_transaction(account: @account).transaction

    ApplyRulesJob.perform_now(@family)

    assert_includes transaction.reload.tags, @business_tag
  end
end
