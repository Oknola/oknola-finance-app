# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
class AddOknolaSide < ActiveRecord::Migration[8.1]
  def up
    execute "SET LOCAL lock_timeout = '10s'"

    execute <<~SQL
      ALTER TABLE accounts
        ADD COLUMN oknola_side varchar NOT NULL DEFAULT 'personal',
        ADD CONSTRAINT chk_accounts_oknola_side
          CHECK (oknola_side IN ('business', 'personal'));
      ALTER TABLE transactions
        ADD COLUMN oknola_side varchar,
        ADD CONSTRAINT chk_transactions_oknola_side
          CHECK (oknola_side IS NULL OR oknola_side IN ('business', 'personal'));
    SQL

    execute <<~SQL
      UPDATE accounts
      SET oknola_side = 'business'
      WHERE EXISTS (
        SELECT 1
        FROM rules
        JOIN rule_conditions ON rule_conditions.rule_id = rules.id
        JOIN rule_actions ON rule_actions.rule_id = rules.id
        JOIN tags ON tags.id::text = rule_actions.value
          AND tags.family_id = accounts.family_id
        WHERE rules.family_id = accounts.family_id
          AND rules.resource_type = 'transaction'
          AND rules.name LIKE 'Side: %'
          AND rule_conditions.condition_type = 'transaction_account'
          AND rule_conditions.operator = '='
          AND rule_conditions.value = accounts.id::text
          AND rule_actions.action_type = 'set_transaction_tags'
          AND tags.name = 'Business'
          AND (SELECT COUNT(*) FROM rule_conditions WHERE rule_id = rules.id) = 1
          AND (SELECT COUNT(*) FROM rule_actions WHERE rule_id = rules.id) = 1
      );
    SQL

    execute <<~SQL
      WITH tagged_sides AS (
        SELECT entries.entryable_id AS transaction_id, MIN(tags.name) AS side
        FROM entries
        JOIN accounts ON accounts.id = entries.account_id
        JOIN taggings ON taggings.taggable_id = entries.entryable_id
          AND taggings.taggable_type = 'Transaction'
        JOIN tags ON tags.id = taggings.tag_id
          AND tags.family_id = accounts.family_id
          AND tags.name IN ('Business', 'Personal')
        WHERE entries.entryable_type = 'Transaction'
        GROUP BY entries.entryable_id
        HAVING COUNT(DISTINCT tags.id) = 1
      )
      UPDATE transactions
      SET oknola_side = CASE tagged_sides.side
        WHEN 'Business' THEN 'business'
        ELSE 'personal'
      END
      FROM tagged_sides
      JOIN entries ON entries.entryable_id = tagged_sides.transaction_id
        AND entries.entryable_type = 'Transaction'
      JOIN accounts ON accounts.id = entries.account_id
      WHERE transactions.id = tagged_sides.transaction_id
        AND (CASE tagged_sides.side WHEN 'Business' THEN 'business' ELSE 'personal' END) <> accounts.oknola_side;
    SQL

    execute <<~SQL
      UPDATE rules
      SET active = false
      WHERE resource_type = 'transaction'
        AND name LIKE 'Side: %'
        AND (SELECT COUNT(*) FROM rule_conditions WHERE rule_id = rules.id) = 1
        AND (SELECT COUNT(*) FROM rule_actions WHERE rule_id = rules.id) = 1
        AND EXISTS (
          SELECT 1
          FROM rule_conditions
          JOIN accounts ON accounts.id::text = rule_conditions.value
            AND accounts.family_id = rules.family_id
          JOIN rule_actions ON rule_actions.rule_id = rules.id
          JOIN tags ON tags.id::text = rule_actions.value
            AND tags.family_id = rules.family_id
          WHERE rule_conditions.rule_id = rules.id
            AND rule_conditions.condition_type = 'transaction_account'
            AND rule_conditions.operator = '='
            AND rule_actions.action_type = 'set_transaction_tags'
            AND tags.name IN ('Business', 'Personal')
        );
    SQL
  end

  def down
    execute <<~SQL
      UPDATE rules
      SET active = true
      WHERE resource_type = 'transaction'
        AND name LIKE 'Side: %'
        AND (SELECT COUNT(*) FROM rule_conditions WHERE rule_id = rules.id) = 1
        AND (SELECT COUNT(*) FROM rule_actions WHERE rule_id = rules.id) = 1
        AND EXISTS (
          SELECT 1
          FROM rule_conditions
          JOIN accounts ON accounts.id::text = rule_conditions.value
            AND accounts.family_id = rules.family_id
          JOIN rule_actions ON rule_actions.rule_id = rules.id
          JOIN tags ON tags.id::text = rule_actions.value
            AND tags.family_id = rules.family_id
          WHERE rule_conditions.rule_id = rules.id
            AND rule_conditions.condition_type = 'transaction_account'
            AND rule_conditions.operator = '='
            AND rule_actions.action_type = 'set_transaction_tags'
            AND tags.name IN ('Business', 'Personal')
        );
    SQL

    execute <<~SQL
      ALTER TABLE transactions
        DROP CONSTRAINT chk_transactions_oknola_side,
        DROP COLUMN oknola_side;
      ALTER TABLE accounts
        DROP CONSTRAINT chk_accounts_oknola_side,
        DROP COLUMN oknola_side;
    SQL
  end
end
