# Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0
module Oknola
  class Side
    NAMES = %w[Business Personal].freeze

    def self.for(transaction)
      tag_names = transaction.tags.map(&:name)
      NAMES.find { |name| tag_names.include?(name) }
    end

    def self.available?(family)
      family.tags.where(name: NAMES).count == 2
    end
  end
end
