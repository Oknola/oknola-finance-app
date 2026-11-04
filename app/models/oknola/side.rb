# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
module Oknola
  class Side
    NAMES = %w[Business Personal].freeze

    def self.for(transaction)
      side = transaction.oknola_side.presence || transaction.entry.account.oknola_side
      side.capitalize
    end
  end
end
