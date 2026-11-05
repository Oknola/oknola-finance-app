# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
class AddOknolaSideToBudgets < ActiveRecord::Migration[7.2]
  def up
    add_column :budgets, :oknola_side, :string, default: "personal", null: false
    add_check_constraint :budgets, "oknola_side IN ('business', 'personal')", name: "chk_budgets_oknola_side"

    remove_index :budgets, name: "index_budgets_personal_unique"
    remove_index :budgets, name: "index_budgets_shared_unique"

    add_index :budgets,
              [ :family_id, :start_date, :end_date, :user_id, :oknola_side ],
              unique: true,
              where: "user_id IS NOT NULL",
              name: "index_budgets_personal_unique"

    add_index :budgets,
              [ :family_id, :start_date, :end_date, :oknola_side ],
              unique: true,
              where: "user_id IS NULL",
              name: "index_budgets_shared_unique"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
