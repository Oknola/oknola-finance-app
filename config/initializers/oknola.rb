# frozen_string_literal: true

# Oknola Finance App hardening: production boot checks and the handoff throttle.
require Rails.root.join("lib/active_record_encryption_config").to_s

module OknolaHardening
  module_function

  def boot_errors(env: ENV, cache: Rails.cache, posthog: Rails.configuration.x.posthog)
    errors = []
    unless ActiveRecordEncryptionConfig.complete_env?(env)
      errors << "set all of #{ActiveRecordEncryptionConfig::ENV_KEYS.join(', ')}"
    end
    errors << "set POSTHOG_FEEDBACK_ENABLED=false" unless posthog&.feedback_enabled == false
    # One-time sign-in codes are minted by one web process and redeemed by
    # another, so the cache must be shared (Redis, from REDIS_URL).
    errors << "set REDIS_URL so Rails.cache is shared" unless cache.is_a?(ActiveSupport::Cache::RedisCacheStore)
    errors
  end

  def verify!(**options)
    errors = boot_errors(**options)
    raise "Oknola production configuration incomplete: #{errors.join('; ')}" if errors.any?
  end
end

# After initialization, so posthog.rb and the cache store are configured. The
# image build precompiles assets in production with a dummy secret and no
# runtime environment, so it is skipped there.
Rails.application.config.after_initialize do
  OknolaHardening.verify! if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
end

Rack::Attack.throttle("oknola/handoff", limit: 20, period: 1.minute) do |request|
  request.ip if request.path.start_with?("/oknola/")
end
