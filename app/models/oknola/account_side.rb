module Oknola
  module AccountSide
    SIDES = %w[business personal mixed].freeze

    module_function

    def available?(family)
      return false unless family

      family.tags.where(name: %w[Business Personal]).distinct.pluck(:name).sort == %w[Business Personal]
    end

    def rule_for(account)
      account.family.rules
        .where(resource_type: "transaction")
        .where("name LIKE ?", "Side: %")
        .includes(:conditions, :actions)
        .find do |rule|
          rule.conditions.one? &&
            rule.conditions.first.condition_type == "transaction_account" &&
            rule.conditions.first.operator == "=" &&
            rule.conditions.first.value == account.id.to_s &&
            rule.actions.one? &&
            rule.actions.first.action_type == "set_transaction_tags"
        end
    end

    def side_for(account)
      action = rule_for(account)&.actions&.first
      return "mixed" unless action

      case account.family.tags.find_by(id: action.value)&.name
      when "Business" then "business"
      when "Personal" then "personal"
      else "mixed"
      end
    end

    def set(account, side)
      return side unless SIDES.include?(side) && available?(account.family)

      if side == "mixed"
        rule_for(account)&.destroy!
        return side
      end

      family = account.family
      selected_tag = family.tags.find_by!(name: side.capitalize)
      other_tag = family.tags.find_by(name: (side == "business" ? "Personal" : "Business"))

      rule = Account.transaction do
        if other_tag
          Tagging.where(
            taggable_type: "Transaction",
            taggable_id: account.transactions.select(:id),
            tag_id: other_tag.id
          ).delete_all
        end

        rule = rule_for(account)
        condition_attributes = {
          condition_type: "transaction_account",
          operator: "=",
          value: account.id.to_s
        }
        action_attributes = {
          action_type: "set_transaction_tags",
          value: selected_tag.id.to_s
        }

        if rule
          rule.update!(
            name: "Side: #{account.name}",
            active: true,
            conditions_attributes: [ condition_attributes.merge(id: rule.conditions.first.id) ],
            actions_attributes: [ action_attributes.merge(id: rule.actions.first.id) ]
          )
        else
          rule = family.rules.create!(
            name: "Side: #{account.name}",
            resource_type: "transaction",
            active: true,
            conditions: [ Rule::Condition.new(condition_attributes) ],
            actions: [ Rule::Action.new(action_attributes) ]
          )
        end

        rule
      end

      rule.apply_later(ignore_attribute_locks: true)
      side
    end
  end
end
