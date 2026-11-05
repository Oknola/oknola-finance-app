# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
module Oknola
  module QuickEntry
    module_function

    def account_sides(accounts)
      accounts.to_h { |account| [ account.id, AccountSide.side_for(account) ] }
    end
  end
end
