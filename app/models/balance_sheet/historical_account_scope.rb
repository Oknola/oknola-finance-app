# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
class BalanceSheet::HistoricalAccountScope
  def initialize(family, user: nil, side: Current.side)
    @family = family
    @user = user
    @side = side
  end

  def account_ids
    relation.pluck(:id)
  end

  def relation
    scope = family.accounts.historical.included_in_reports
    scope = scope.included_in_finances_for(user) if user.present?
    scope = scope.where(oknola_side: side) if side.present?
    scope
  end

  private
    attr_reader :family, :user, :side
end
