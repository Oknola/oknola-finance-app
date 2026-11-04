module Oknola
  module QuickEntry
    module_function

    def side_tags(family)
      tags = family.tags.where(name: %w[Business Personal]).pluck(:name, :id).to_h
      return {} unless tags.size == 2

      { "business" => tags.fetch("Business"), "personal" => tags.fetch("Personal") }
    end

    def account_sides(family, accounts)
      tags = side_tags(family)
      return {} if tags.empty?

      accounts.to_h { |account| [ account.id, tags[AccountSide.side_for(account)] ] }
    end
  end
end
