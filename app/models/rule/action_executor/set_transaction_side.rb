class Rule::ActionExecutor::SetTransactionSide < Rule::ActionExecutor
  def type
    "select"
  end

  def options
    [
      [ I18n.t("oknola.side_switch.business"), "business" ],
      [ I18n.t("oknola.side_switch.personal"), "personal" ]
    ]
  end

  def claimed_attributes
    [ :oknola_side ]
  end

  def actionable?(value)
    Oknola::AccountSide::SIDES.include?(value)
  end

  def execute(transaction_scope, value: nil, ignore_attribute_locks: false, rule_run: nil)
    return 0 unless actionable?(value)

    scope = transaction_scope.includes(entry: :account)
    scope = scope.enrichable(:oknola_side) unless ignore_attribute_locks

    count_modified_resources(scope) do |txn|
      side = value == txn.entry.account.oknola_side ? nil : value

      txn.enrich_attribute(
        :oknola_side,
        side,
        source: "rule",
        ignore_locks: ignore_attribute_locks
      )
    end
  end
end
