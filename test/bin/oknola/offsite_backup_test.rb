# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
require "minitest/autorun"
require "mocha/minitest"
require "climate_control"
require "open3"
require "json"
require "uri"
require "tmpdir"
require "stringio"
load File.expand_path("../../../bin/oknola-offsite-backup", __dir__)

class OknolaOffsiteBackupTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("offsite-backup-test")
    @env = {
      "DATABASE_URL" => "postgres://backup-user:#{URI.encode_www_form_component('backup@test+password')}@backup-test.invalid/finance",
      "R2_ACCOUNT_ID" => "test-account",
      "R2_ACCESS_KEY_ID" => "test-access",
      "R2_SECRET_ACCESS_KEY" => "test-secret",
      "R2_BUCKET" => "test-bucket",
      "PATH" => "#{@directory}:#{ENV.fetch('PATH')}",
      "BACKUP_TEST_LOG" => File.join(@directory, "commands.jsonl"),
      "BACKUP_TEST_DUMP_EXIT" => "0",
      "BACKUP_TEST_RESTORE_EXIT" => "0"
    }
    %w[pg_dump pg_restore].each do |command|
      path = File.join(@directory, command)
      File.write(path, <<~RUBY)
        #!#{RbConfig.ruby}
        require "json"
        require "uri"
        File.open(ENV.fetch("BACKUP_TEST_LOG"), "a") { |log| log.puts JSON.generate([File.basename($0), ARGV, File.umask]) }
        if File.basename($0) == "pg_dump"
          File.write(ARGV.find { |arg| arg.start_with?("--file=") }.delete_prefix("--file="), "archive")
          File.write(ENV.fetch("BACKUP_TEST_LOG") + ".password", ENV["PGPASSWORD"].to_s)
          warn "pg_dump: connection refused"
          warn ENV.fetch("DATABASE_URL")
          warn ENV["PGPASSWORD"]
          warn URI.encode_www_form_component(ENV["PGPASSWORD"].to_s)
          exit ENV.fetch("BACKUP_TEST_DUMP_EXIT").to_i
        end
        exit ENV.fetch("BACKUP_TEST_RESTORE_EXIT").to_i
      RUBY
      File.chmod(0o755, path)
    end
    @stdout, @stderr = StringIO.new, StringIO.new
    @storage = mock("S3 resource")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_missing_environment_exits_one_and_prints_names_not_values
    OknolaOffsiteBackup::REQUIRED_ENV.each do |missing|
      stdout, stderr, status = Open3.capture3(@env.merge(missing => nil),
        RbConfig.ruby, File.expand_path("../../../bin/oknola-offsite-backup", __dir__))

      assert_equal 1, status.exitstatus
      assert_includes stderr, missing
      @env.values_at(*OknolaOffsiteBackup::REQUIRED_ENV).each do |value|
        refute_includes stdout + stderr, value
      end
    end
    refute File.exist?(@env.fetch("BACKUP_TEST_LOG"))
  end

  def test_empty_environment_is_missing
    @env["R2_BUCKET"] = ""
    @storage.expects(:bucket).never
    assert_equal 1, run_backup
    assert_includes @stderr.string, "R2_BUCKET"
    refute File.exist?(@env.fetch("BACKUP_TEST_LOG"))
  end

  def test_dump_failure_aborts_without_upload_and_removes_temp_file
    @env["BACKUP_TEST_DUMP_EXIT"] = "1"
    stdout, stderr, status = run_script

    assert_equal 1, status.exitstatus
    assert_equal [ "pg_dump" ], commands.map(&:first)
    assert_includes stderr, "pg_dump failed"
    assert_includes stderr, "connection refused"
    assert_includes stderr, "[REDACTED]"
    refute_includes stdout + stderr, @env.fetch("DATABASE_URL")
    refute_includes stdout + stderr, "backup@test+password"
    refute_includes stdout + stderr, "backup%40test%2Bpassword"
    refute_includes commands.first[1].join(" "), "password"
    refute File.exist?(dump_path)
  end

  def test_dump_failure_never_initializes_storage
    @env["BACKUP_TEST_DUMP_EXIT"] = "1"
    @storage.expects(:bucket).never
    Aws::S3::Resource.expects(:new).never

    assert_equal 1, run_backup(storage: nil)
    refute File.exist?(dump_path)
  end

  def test_restore_failure_aborts_without_upload_and_removes_temp_file
    @env["BACKUP_TEST_RESTORE_EXIT"] = "1"
    @storage.expects(:bucket).never

    assert_equal 1, run_backup
    assert_equal [ "pg_dump", "pg_restore" ], commands.map(&:first)
    assert_includes @stderr.string, "pg_restore validation failed"
    refute File.exist?(dump_path)
  end

  def test_success_uploads_validated_private_archive_to_timestamped_key_and_removes_it
    Aws::S3::Resource.expects(:new).with(
      endpoint: "https://test-account.r2.cloudflarestorage.com",
      region: "auto", access_key_id: "test-access", secret_access_key: "test-secret",
      request_checksum_calculation: "when_required", response_checksum_validation: "when_required"
    ).returns(@storage)
    object = expect_upload
    object.expects(:upload_file).with { |path|
      assert_equal dump_path, path
      assert_equal "archive", File.read(path)
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal [ "pg_dump", "pg_restore" ], commands.map(&:first)
      true
    }.returns(true)
    old_umask = File.umask

    assert_equal 0, run_backup(storage: nil)
    assert_equal old_umask, File.umask
    assert_equal 0o077, commands.first.last
    assert_equal [ "--format=custom", "--no-owner", "--no-privileges",
      "--dbname=postgres://backup-user@backup-test.invalid/finance", "--file=#{dump_path}" ], commands.first[1]
    assert_equal "backup@test+password", File.read(@env.fetch("BACKUP_TEST_LOG") + ".password")
    assert_equal [ "--list", dump_path ], commands.last[1]
    refute File.exist?(dump_path)
    assert_match %r{Uploaded finance-db/\d{4}-\d{2}-\d{2}T\d{6}Z\.dump}, @stdout.string
    refute_includes @stdout.string + @stderr.string, @env.fetch("DATABASE_URL")
    refute_includes @stdout.string + @stderr.string, "backup@test+password"
  end

  def test_query_password_is_removed_from_arguments_and_redacted_on_failure
    @env["DATABASE_URL"] = "postgres://backup-user@backup-test.invalid/finance?sslmode=require&options=-c%20statement_timeout%3D0&#{'password'}=query+password"
    @env["BACKUP_TEST_DUMP_EXIT"] = "1"
    stdout, stderr, status = run_script

    assert_equal 1, status.exitstatus
    assert_includes commands.first[1], "--dbname=postgres://backup-user@backup-test.invalid/finance?sslmode=require&options=-c%20statement_timeout%3D0"
    assert_equal "query+password", File.read(@env.fetch("BACKUP_TEST_LOG") + ".password")
    refute_includes stdout + stderr, @env.fetch("DATABASE_URL")
    refute_includes stdout + stderr, "query+password"
    refute_includes stdout + stderr, "query%2Bpassword"
    assert_includes stderr, "connection refused"
    refute File.exist?(dump_path)
  end

  def test_password_free_url_does_not_inherit_pgpassword
    @env["DATABASE_URL"] = "postgres://backup-user@backup-test.invalid/finance"
    @env["PGPASSWORD"] = "stale-test-password"
    @env["BACKUP_TEST_DUMP_EXIT"] = "1"
    stdout, stderr, status = run_script

    assert_equal 1, status.exitstatus
    assert_includes commands.first[1], "--dbname=#{@env.fetch('DATABASE_URL')}"
    assert_empty File.read(@env.fetch("BACKUP_TEST_LOG") + ".password")
    refute_includes stdout + stderr, @env.fetch("DATABASE_URL")
    refute_includes stdout + stderr, @env.fetch("PGPASSWORD")
    refute File.exist?(dump_path)
  end

  def test_upload_failure_exits_one_removes_temp_file_and_hides_exception_details
    expect_upload.expects(:upload_file).raises(StandardError, @env.fetch("DATABASE_URL"))

    assert_equal 1, run_backup
    refute File.exist?(dump_path)
    assert_includes @stderr.string, "Backup failed"
    refute_includes @stderr.string, @env.fetch("DATABASE_URL")
  end

  private
    def run_script
      Open3.capture3(@env, RbConfig.ruby, File.expand_path("../../../bin/oknola-offsite-backup", __dir__))
    end

    def run_backup(storage: @storage)
      ClimateControl.modify(@env) do
        OknolaOffsiteBackup.new(storage: storage, stdout: @stdout, stderr: @stderr).run
      end
    end

    def commands
      File.readlines(@env.fetch("BACKUP_TEST_LOG")).map { |line| JSON.parse(line) }
    end

    def dump_path
      commands.first[1].find { |arg| arg.start_with?("--file=") }.delete_prefix("--file=")
    end

    def expect_upload
      bucket, object = mock("bucket"), mock("object")
      @storage.expects(:bucket).with("test-bucket").returns(bucket)
      bucket.expects(:object).with(regexp_matches(%r{\Afinance-db/\d{4}-\d{2}-\d{2}T\d{6}Z\.dump\z})).returns(object)
      object
    end
end
