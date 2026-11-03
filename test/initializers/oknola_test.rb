require "test_helper"

class OknolaBootCheckTest < ActiveSupport::TestCase
  COMPLETE_ENV = {
    "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "primary",
    "ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY" => "deterministic",
    "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => "salt"
  }.freeze

  setup do
    @redis_cache = ActiveSupport::Cache::RedisCacheStore.new(url: "redis://localhost:6379/0")
    @feedback_off = ActiveSupport::OrderedOptions.new.tap { |config| config.feedback_enabled = false }
  end

  test "a complete production configuration boots" do
    assert_nothing_raised do
      OknolaHardening.verify!(env: COMPLETE_ENV, cache: @redis_cache, posthog: @feedback_off)
    end
  end

  test "missing encryption env vars stop the boot" do
    [ {}, COMPLETE_ENV.except("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT") ].each do |env|
      error = assert_raises(RuntimeError) do
        OknolaHardening.verify!(env: env, cache: @redis_cache, posthog: @feedback_off)
      end
      assert_includes error.message, "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"
    end
  end

  test "PostHog feedback left on stops the boot" do
    feedback_on = ActiveSupport::OrderedOptions.new.tap { |config| config.feedback_enabled = true }

    error = assert_raises(RuntimeError) do
      OknolaHardening.verify!(env: COMPLETE_ENV, cache: @redis_cache, posthog: feedback_on)
    end
    assert_includes error.message, "POSTHOG_FEEDBACK_ENABLED=false"
  end

  test "a per-process cache stops the boot" do
    error = assert_raises(RuntimeError) do
      OknolaHardening.verify!(env: COMPLETE_ENV, cache: ActiveSupport::Cache::MemoryStore.new, posthog: @feedback_off)
    end
    assert_includes error.message, "REDIS_URL"
  end
end

class OknolaThrottleTest < ActionDispatch::IntegrationTest
  setup do
    @original_enabled = Rack::Attack.enabled
    @original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
  end

  teardown do
    Rack::Attack.enabled = @original_enabled
    Rack::Attack.cache.store = @original_store
  end

  test "the 21st Oknola call in a minute from one IP is throttled" do
    # Counters are bucketed per period; a frozen clock keeps all calls in one.
    freeze_time
    20.times do
      post oknola_handoff_path, params: {}, as: :json
      assert_response :unauthorized
    end

    post oknola_handoff_path, params: {}, as: :json
    assert_response :too_many_requests

    delete oknola_account_path(sub: "any")
    assert_response :too_many_requests
  end
end
