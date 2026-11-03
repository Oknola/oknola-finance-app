# frozen_string_literal: true

# Oknola Finance App: one row per notice a user has accepted (the early-access
# notice first), so each is shown once and the date is on record. Deleting the
# user deletes their rows.
class CreateOknolaAcceptances < ActiveRecord::Migration[8.1]
  def change
    create_table :oknola_acceptances, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, index: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :version, null: false
      t.datetime :accepted_at, null: false
      t.timestamps
    end

    # Also serves the per-user lookup, so user_id needs no index of its own.
    add_index :oknola_acceptances, %i[user_id kind version], unique: true
  end
end
