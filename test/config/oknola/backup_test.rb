# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
require "minitest/autorun"
require "yaml"

class OknolaBackupBlueprintTest < Minitest::Test
  def test_backup_uses_internal_database_and_only_its_own_secrets
    blueprint = YAML.safe_load_file(File.expand_path("../../../render.yaml", __dir__))
    backup = blueprint.fetch("services").find { |service| service["name"] == "finance-backup" }
    web = blueprint.fetch("services").find { |service| service["name"] == "finance-web" }
    database = blueprint.fetch("databases").find { |db| db["name"] == "finance-db" }

    assert_equal "cron", backup.fetch("type")
    assert_equal "image", backup.fetch("runtime")
    assert_equal web.fetch("image"), backup.fetch("image")
    assert_equal "ohio", backup.fetch("region")
    assert_equal "starter", backup.fetch("plan")
    assert_equal "17 6 * * 0", backup.fetch("schedule")
    assert_equal "bundle exec ruby bin/oknola-offsite-backup", backup.fetch("dockerCommand")
    assert_equal [], database.fetch("ipAllowList")
    env = backup.fetch("envVars")
    assert_equal({ "key" => "DATABASE_URL",
      "fromDatabase" => { "name" => "finance-db", "property" => "connectionString" } },
      env.find { |entry| entry["key"] == "DATABASE_URL" })
    assert_equal %w[DATABASE_URL R2_ACCESS_KEY_ID R2_ACCOUNT_ID R2_BUCKET R2_SECRET_ACCESS_KEY],
      env.map { |entry| entry.fetch("key") }.sort
    env.reject { |entry| entry["key"] == "DATABASE_URL" }.each do |entry|
      assert_equal({ "key" => entry.fetch("key"), "sync" => false }, entry)
    end
    refute File.exist?(File.expand_path("../../../.github/workflows/backup-offsite.yml", __dir__))
  end
end
