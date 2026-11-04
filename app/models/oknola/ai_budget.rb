# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
module Oknola
  class AiBudget
    class Exceeded < Provider::Error; end

    def self.remaining(family)
      start_of_month = Time.current.utc.beginning_of_month
      end_of_month = start_of_month.next_month
      usages = family.llm_usages.where(created_at: start_of_month...end_of_month)
      priced_spend = usages.sum(:estimated_cost).to_d
      unpriced_spend = usages.where(estimated_cost: nil).sum do |usage|
        unpriced_usage_cost(usage)
      end

      ENV.fetch("OKNOLA_AI_MONTHLY_USD", "3.00").to_d - priced_spend - unpriced_spend
    end

    def self.check!(family)
      return if family.nil? || remaining(family).positive?

      raise Exceeded, "Monthly AI allowance exceeded"
    end

    def self.user_message
      reset_date = Time.current.utc.next_month.beginning_of_month.to_date
      I18n.t("chats.ai_budget_exceeded", reset_date: I18n.l(reset_date, format: :long))
    end

    def self.unpriced_usage_cost(usage)
      rates = LlmUsage::PRICING.fetch("anthropic").values.flat_map do |pricing|
        [ pricing, pricing[:long_context] ].compact
      end
      prompt_rate = rates.map { |pricing| pricing[:prompt] }.max.to_d
      completion_rate = rates.map { |pricing| pricing[:completion] }.max.to_d

      (
        usage.prompt_tokens.to_d * prompt_rate +
        usage.completion_tokens.to_d * completion_rate
      ) / 1_000_000
    end
    private_class_method :unpriced_usage_cost
  end
end
