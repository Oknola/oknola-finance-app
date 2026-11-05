# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
class BalanceSheet::NetWorthSeriesBuilder
  def initialize(family, user: nil, side: Current.side)
    @family = family
    @user = user
    @side = side
  end

  def net_worth_series(period: Period.last_30_days)
    Rails.cache.fetch(cache_key(period)) do
      builder = Balance::ChartSeriesBuilder.new(
        account_ids: historical_account_ids,
        account_active_until_dates: disabled_account_active_until_dates,
        currency: family.currency,
        period: period,
        favorable_direction: "up"
      )

      builder.balance_series
    end
  end

  private
    attr_reader :family, :user, :side

    def historical_accounts
      @historical_accounts ||= historical_account_scope.relation.to_a
    end

    def historical_account_ids
      @historical_account_ids ||= historical_accounts.map(&:id)
    end

    def disabled_account_active_until_dates
      @disabled_account_active_until_dates ||= historical_accounts.each_with_object({}) do |account, dates|
        next unless account.disabled?

        disabled_on = (account.disabled_at || account.updated_at).to_date
        dates[account.id] = disabled_on - 1.day
      end
    end

    def historical_account_scope
      @historical_account_scope ||= BalanceSheet::HistoricalAccountScope.new(family, user: user, side: side)
    end

    def cache_key(period)
      shares_version = user ? AccountShare.where(user: user).maximum(:updated_at)&.to_i : nil
      key = [
        "balance_sheet_net_worth_series_historical",
        user&.id,
        shares_version,
        side,
        period.start_date,
        period.end_date
      ].compact.join("_")

      family.build_cache_key(
        key,
        invalidate_on_data_updates: true
      )
    end
end
