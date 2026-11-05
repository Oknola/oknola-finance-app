# frozen_string_literal: true

# Modified by Cardona Labs, LLC, 2026-11-05, AGPL-3.0
# Oknola Finance App hardening: production boot checks and the handoff throttle.
require Rails.root.join("lib/active_record_encryption_config").to_s

# The upstream Doorkeeper URI policy still reads this legacy constant.
module OauthRegistrationController
  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1].freeze
end

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

  # The shared bearer check for calls from the Oknola server. A blank or
  # unset OKNOLA_HANDOFF_SECRET rejects every call.
  def secret_valid?(authorization, env: ENV)
    expected = env["OKNOLA_HANDOFF_SECRET"].to_s
    return false if expected.blank?

    scheme, token = authorization.to_s.split(" ", 2)
    scheme == "Bearer" && token.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
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

# Code redemption comes from users' browsers, one IP each.
Rack::Attack.throttle("oknola/session/ip", limit: 20, period: 1.minute) do |request|
  request.ip if request.path == "/oknola/session"
end

# Server calls arrive from the Oknola server's shared egress IPs, so only
# calls with a missing or wrong secret count; the right secret is never throttled.
Rack::Attack.throttle("oknola/bad-secret/ip", limit: 10, period: 1.minute) do |request|
  server_path = request.path == "/oknola/handoff" || request.path.start_with?("/oknola/accounts/")
  request.ip if server_path && !OknolaHardening.secret_valid?(request.get_header("HTTP_AUTHORIZATION"))
end
