# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
module Oknola
  module AccountSide
    SIDES = %w[business personal].freeze

    module_function

    def side_for(account)
      account.oknola_side
    end

    def set(account, side)
      return false unless SIDES.include?(side)

      Account.transaction do
        account.update!(oknola_side: side)
        account.transactions.where(oknola_side: side).update_all(oknola_side: nil)
        side
      end
    end
  end
end
