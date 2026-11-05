# Modified by Cardona Labs, LLC, 2026-11-04, AGPL-3.0
require "test_helper"
require_relative "../../db/migrate/20261104120000_add_oknola_side"

class AddOknolaSideTest < ActiveSupport::TestCase
  BUSINESS_ACCOUNT = "10000000-0000-0000-0000-000000000001"
  PERSONAL_ACCOUNT = "10000000-0000-0000-0000-000000000002"
  UNASSIGNED_ACCOUNT = "10000000-0000-0000-0000-000000000003"
  FAMILY_ID = "20000000-0000-0000-0000-000000000001"
  BUSINESS_TAG = "30000000-0000-0000-0000-000000000001"
  PERSONAL_TAG = "30000000-0000-0000-0000-000000000002"
  BUSINESS_RULE = "40000000-0000-0000-0000-000000000001"
  PERSONAL_RULE = "40000000-0000-0000-0000-000000000002"
  BUSINESS_TRANSACTION = "50000000-0000-0000-0000-000000000001"
  PERSONAL_TRANSACTION = "50000000-0000-0000-0000-000000000002"
  BOTH_TAGS_TRANSACTION = "50000000-0000-0000-0000-000000000003"
  PERSONAL_OVERRIDE_TRANSACTION = "50000000-0000-0000-0000-000000000004"
  OTHER_FAMILY_ID = "20000000-0000-0000-0000-000000000002"
  OTHER_TAG = "30000000-0000-0000-0000-000000000003"
  OTHER_FAMILY_BUSINESS_TAG = "30000000-0000-0000-0000-000000000004"
  OTHER_TAG_RULE = "40000000-0000-0000-0000-000000000003"
  CROSS_FAMILY_RULE = "40000000-0000-0000-0000-000000000004"

  test "backfills unambiguous account and transaction sides and reverses the migration" do
    create_legacy_tables
    create_legacy_data

    AddOknolaSide.new.up

    assert_equal "business", side_for("accounts", BUSINESS_ACCOUNT)
    assert_equal "personal", side_for("accounts", PERSONAL_ACCOUNT)
    assert_equal "personal", side_for("accounts", UNASSIGNED_ACCOUNT)
    assert_equal "business", side_for("transactions", BUSINESS_TRANSACTION)
    assert_nil side_for("transactions", PERSONAL_TRANSACTION)
    assert_nil side_for("transactions", BOTH_TAGS_TRANSACTION)
    assert_equal "personal", side_for("transactions", PERSONAL_OVERRIDE_TRANSACTION)
    assert_equal [ false, false, true, true ], connection.select_values("SELECT active FROM rules ORDER BY id")

    assert_raises(ActiveRecord::StatementInvalid) do
      connection.transaction(requires_new: true) do
        connection.execute("UPDATE accounts SET oknola_side = 'mixed' WHERE id = '#{PERSONAL_ACCOUNT}'")
      end
    end

    AddOknolaSide.new.down

    assert_equal [ true, true, true, true ], connection.select_values("SELECT active FROM rules ORDER BY id")
    assert_equal 0, column_count("accounts")
    assert_equal 0, column_count("transactions")
  end

  private
    def connection
      ActiveRecord::Base.connection
    end

    def create_legacy_tables
      connection.execute("CREATE TEMP TABLE accounts (id uuid, family_id uuid, name varchar)")
      connection.execute("CREATE TEMP TABLE transactions (id uuid)")
      connection.execute("CREATE TEMP TABLE entries (entryable_id uuid, entryable_type varchar, account_id uuid)")
      connection.execute("CREATE TEMP TABLE rules (id uuid, family_id uuid, name varchar, resource_type varchar, active boolean)")
      connection.execute("CREATE TEMP TABLE rule_conditions (rule_id uuid, condition_type varchar, operator varchar, value varchar)")
      connection.execute("CREATE TEMP TABLE rule_actions (rule_id uuid, action_type varchar, value varchar)")
      connection.execute("CREATE TEMP TABLE tags (id uuid, family_id uuid, name varchar)")
      connection.execute("CREATE TEMP TABLE taggings (taggable_id uuid, taggable_type varchar, tag_id uuid)")
    end

    def create_legacy_data
      connection.execute(<<~SQL)
        INSERT INTO accounts (id, family_id, name) VALUES
          ('#{BUSINESS_ACCOUNT}', '#{FAMILY_ID}', 'Business account'),
          ('#{PERSONAL_ACCOUNT}', '#{FAMILY_ID}', 'Personal account'),
          ('#{UNASSIGNED_ACCOUNT}', '#{FAMILY_ID}', 'Unassigned account');
        INSERT INTO tags (id, family_id, name) VALUES
          ('#{BUSINESS_TAG}', '#{FAMILY_ID}', 'Business'),
          ('#{PERSONAL_TAG}', '#{FAMILY_ID}', 'Personal'),
          ('#{OTHER_TAG}', '#{FAMILY_ID}', 'Other'),
          ('#{OTHER_FAMILY_BUSINESS_TAG}', '#{OTHER_FAMILY_ID}', 'Business');
        INSERT INTO rules (id, family_id, name, resource_type, active) VALUES
          ('#{BUSINESS_RULE}', '#{FAMILY_ID}', 'Side: Business account', 'transaction', true),
          ('#{PERSONAL_RULE}', '#{FAMILY_ID}', 'Side: Personal account', 'transaction', true),
          ('#{OTHER_TAG_RULE}', '#{FAMILY_ID}', 'Side: Other tag', 'transaction', true),
          ('#{CROSS_FAMILY_RULE}', '#{FAMILY_ID}', 'Side: Foreign Business tag', 'transaction', true);
        INSERT INTO rule_conditions (rule_id, condition_type, operator, value) VALUES
          ('#{BUSINESS_RULE}', 'transaction_account', '=', '#{BUSINESS_ACCOUNT}'),
          ('#{PERSONAL_RULE}', 'transaction_account', '=', '#{PERSONAL_ACCOUNT}'),
          ('#{OTHER_TAG_RULE}', 'transaction_account', '=', '#{BUSINESS_ACCOUNT}'),
          ('#{CROSS_FAMILY_RULE}', 'transaction_account', '=', '#{UNASSIGNED_ACCOUNT}');
        INSERT INTO rule_actions (rule_id, action_type, value) VALUES
          ('#{BUSINESS_RULE}', 'set_transaction_tags', '#{BUSINESS_TAG}'),
          ('#{PERSONAL_RULE}', 'set_transaction_tags', '#{PERSONAL_TAG}'),
          ('#{OTHER_TAG_RULE}', 'set_transaction_tags', '#{OTHER_TAG}'),
          ('#{CROSS_FAMILY_RULE}', 'set_transaction_tags', '#{OTHER_FAMILY_BUSINESS_TAG}');
        INSERT INTO transactions (id) VALUES
          ('#{BUSINESS_TRANSACTION}'),
          ('#{PERSONAL_TRANSACTION}'),
          ('#{BOTH_TAGS_TRANSACTION}'),
          ('#{PERSONAL_OVERRIDE_TRANSACTION}');
        INSERT INTO entries (entryable_id, entryable_type, account_id) VALUES
          ('#{BUSINESS_TRANSACTION}', 'Transaction', '#{PERSONAL_ACCOUNT}'),
          ('#{PERSONAL_TRANSACTION}', 'Transaction', '#{BUSINESS_ACCOUNT}'),
          ('#{BOTH_TAGS_TRANSACTION}', 'Transaction', '#{PERSONAL_ACCOUNT}'),
          ('#{PERSONAL_OVERRIDE_TRANSACTION}', 'Transaction', '#{BUSINESS_ACCOUNT}');
        INSERT INTO taggings (taggable_id, taggable_type, tag_id) VALUES
          ('#{BUSINESS_TRANSACTION}', 'Transaction', '#{BUSINESS_TAG}'),
          ('#{PERSONAL_TRANSACTION}', 'Transaction', '#{BUSINESS_TAG}'),
          ('#{BOTH_TAGS_TRANSACTION}', 'Transaction', '#{BUSINESS_TAG}'),
          ('#{BOTH_TAGS_TRANSACTION}', 'Transaction', '#{PERSONAL_TAG}'),
          ('#{PERSONAL_OVERRIDE_TRANSACTION}', 'Transaction', '#{PERSONAL_TAG}');
      SQL
    end

    def side_for(table, id)
      connection.select_value("SELECT oknola_side FROM #{table} WHERE id = '#{id}'")
    end

    def column_count(table)
      connection.select_value(<<~SQL)
        SELECT COUNT(*)
        FROM pg_attribute
        WHERE attrelid = to_regclass('#{table}')
          AND attname = 'oknola_side'
          AND NOT attisdropped
      SQL
    end
end
