# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
require "minitest/autorun"
require "mocha/minitest"
require "climate_control"
require "open3"
require "json"
require "tmpdir"
require "stringio"
load File.expand_path("../../../bin/oknola-offsite-backup", __dir__)

class OknolaOffsiteBackupTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("offsite-backup-test")
    @env = {
      "DATABASE_URL" => "postgres://backup-test.invalid/finance",
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
        File.open(ENV.fetch("BACKUP_TEST_LOG"), "a") { |log| log.puts JSON.generate([File.basename($0), ARGV, File.umask]) }
        if File.basename($0) == "pg_dump"
          File.write(ARGV.find { |arg| arg.start_with?("--file=") }.delete_prefix("--file="), "archive")
          warn ENV.fetch("DATABASE_URL")
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
    @storage.expects(:bucket).never

    assert_equal 1, run_backup
    assert_equal [ "pg_dump" ], commands.map(&:first)
    assert_includes @stderr.string, "pg_dump failed"
    refute_includes @stderr.string, @env.fetch("DATABASE_URL")
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
      "--dbname=#{@env.fetch('DATABASE_URL')}", "--file=#{dump_path}" ], commands.first[1]
    assert_equal [ "--list", dump_path ], commands.last[1]
    refute File.exist?(dump_path)
    assert_match %r{Uploaded finance-db/\d{4}-\d{2}-\d{2}T\d{6}Z\.dump}, @stdout.string
    refute_includes @stdout.string + @stderr.string, @env.fetch("DATABASE_URL")
  end

  def test_upload_failure_exits_one_removes_temp_file_and_hides_exception_details
    expect_upload.expects(:upload_file).raises(StandardError, @env.fetch("DATABASE_URL"))

    assert_equal 1, run_backup
    refute File.exist?(dump_path)
    assert_includes @stderr.string, "Backup failed"
    refute_includes @stderr.string, @env.fetch("DATABASE_URL")
  end

  private
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
