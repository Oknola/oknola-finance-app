# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
class AutoCategorizeJob < ApplicationJob
  queue_as :ai_low_priority

  def perform(family, transaction_ids: [], rule_run_id: nil)
    rule_run = RuleRun.find_by(id: rule_run_id) if rule_run_id.present?
    modified_count = family.auto_categorize_transactions(transaction_ids)

    # If this job was part of a rule run, report back the modified count
    rule_run&.complete_job!(modified_count: modified_count)
  rescue Oknola::AiBudget::Exceeded => error
    Rails.logger.info("Skipping auto-categorization for family #{family.id}: #{error.message}")
    rule_run&.complete_job!(modified_count: 0)
  rescue => error
    rule_run&.fail_job!(error: error, source: self.class.name, transaction_ids: transaction_ids)

    raise
  end
end
