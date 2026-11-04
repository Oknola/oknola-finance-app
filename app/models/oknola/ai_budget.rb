# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
module Oknola
  class AiBudget
    class Exceeded < Provider::Error; end

    def self.remaining(family)
      start_of_month = Time.current.utc.beginning_of_month
      end_of_month = start_of_month.next_month
      spent = family.llm_usages.where(created_at: start_of_month...end_of_month).sum(:estimated_cost)

      ENV.fetch("OKNOLA_AI_MONTHLY_USD", "3.00").to_d - spent.to_d
    end

    def self.check!(family)
      return if family.nil? || remaining(family).positive?

      raise Exceeded, "Monthly AI allowance exceeded"
    end
  end
end
