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
  SECRET = "test-oknola-handoff-secret-0123456789abcdef".freeze

  setup do
    @original_enabled = Rack::Attack.enabled
    @original_store = Rack::Attack.cache.store
    @original_secret = ENV["OKNOLA_HANDOFF_SECRET"]
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    ENV["OKNOLA_HANDOFF_SECRET"] = SECRET
    # Counters are bucketed per period; a frozen clock keeps all calls in one.
    freeze_time
  end

  teardown do
    Rack::Attack.enabled = @original_enabled
    Rack::Attack.cache.store = @original_store
    ENV["OKNOLA_HANDOFF_SECRET"] = @original_secret
  end

  test "the 21st session call in a minute from one IP is throttled" do
    20.times do
      get oknola_session_path(code: "nope")
      assert_response :redirect
    end

    get oknola_session_path(code: "nope")
    assert_response :too_many_requests
  end

  test "the 11th wrong-secret server call in a minute from one IP is throttled" do
    5.times do
      post oknola_handoff_path, params: {}, headers: bearer("wrong"), as: :json
      assert_response :unauthorized
    end
    5.times do
      delete oknola_account_path(sub: "any")
      assert_response :unauthorized
    end

    post oknola_handoff_path, params: {}, headers: bearer("wrong"), as: :json
    assert_response :too_many_requests
  end

  test "a blank configured secret counts every call as wrong" do
    ENV["OKNOLA_HANDOFF_SECRET"] = ""

    10.times { post oknola_handoff_path, params: {}, headers: bearer(""), as: :json }
    post oknola_handoff_path, params: {}, headers: bearer(""), as: :json

    assert_response :too_many_requests
  end

  test "server calls with the right secret are never throttled" do
    30.times do
      post oknola_handoff_path, params: {}, headers: bearer(SECRET), as: :json
      assert_response :unprocessable_entity
    end

    delete oknola_account_path(sub: "unknown"), headers: bearer(SECRET)
    assert_response :no_content
  end

  private
    def bearer(secret)
      { "Authorization" => "Bearer #{secret}" }
    end
end
