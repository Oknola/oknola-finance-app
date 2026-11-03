require "test_helper"

# Oknola fork: render.yaml is the production Blueprint for finance.oknola.com.
# These checks keep secret values out of it and keep it acceptable to Render.
class RenderYamlTest < ActiveSupport::TestCase
  BLUEPRINT = YAML.safe_load_file(Rails.root.join("render.yaml"))

  # The secrets the owner pastes at the first Blueprint apply (docs/hosting/oknola.md).
  SHARED_SECRETS = %w[
    SECRET_KEY_BASE
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
    ANTHROPIC_API_KEY
    SENTRY_DSN
    SMTP_PASSWORD
    EMAIL_SENDER
  ].freeze
  WEB_ONLY_PROMPTS = %w[OKNOLA_HANDOFF_SECRET ONBOARDING_STATE AUTH_LOCAL_LOGIN_ENABLED].freeze
  SECRETS = (SHARED_SECRETS + %w[OKNOLA_HANDOFF_SECRET]).freeze

  KEY_LIKE = [
    /\h{32,}/,                      # openssl rand -hex output
    %r{[A-Za-z0-9+/=_-]{40,}},      # long base64 / token strings
    /sk-ant-|sk_live_|re_[A-Za-z0-9]{8,}/ # Anthropic, Stripe, Resend key prefixes
  ].freeze

  test "every secret is prompted for (sync: false) wherever it appears, never given a value" do
    entries = all_env_entries
    SECRETS.each do |key|
      found = entries.select { |entry| entry["key"] == key }
      assert found.any?, "#{key} is missing from render.yaml"
      found.each do |entry|
        assert_equal false, entry["sync"], "#{key} must be sync: false"
        assert_not entry.key?("value"), "#{key} must not carry a value"
        assert_not entry.key?("generateValue"), "#{key} must come from the owner, not Render"
      end
    end
  end

  test "the web service prompts for every secret and the sign-up switches; the worker for the shared ones" do
    web_prompts = prompted_keys(service("finance-web"))
    worker_prompts = prompted_keys(service("finance-worker"))

    assert_empty(SHARED_SECRETS + WEB_ONLY_PROMPTS - web_prompts)
    assert_empty(SHARED_SECRETS - worker_prompts)
    assert_not_includes worker_prompts, "OKNOLA_HANDOFF_SECRET"
  end

  test "no value in the file looks like a key" do
    all_env_entries.each do |entry|
      next unless entry.key?("value")

      KEY_LIKE.each do |pattern|
        assert_no_match pattern, entry["value"].to_s, "#{entry['key']} looks like a secret"
      end
    end
  end

  test "environment groups hold plain values only, as Render requires" do
    BLUEPRINT.fetch("envVarGroups").each do |group|
      group.fetch("envVars").each do |entry|
        assert entry.key?("value"), "#{group['name']}/#{entry['key']} needs a plain value"
        assert_not entry.key?("sync"), "#{group['name']}/#{entry['key']}: sync: false is not allowed in a group"
        assert_not(entry.key?("fromDatabase") || entry.key?("fromService"),
          "#{group['name']}/#{entry['key']}: a group cannot reference a service")
      end
    end
  end

  test "both services run the published image in Ohio with the database, Key Value and env group" do
    %w[finance-web finance-worker].each do |name|
      svc = service(name)
      assert_equal "image", svc["runtime"]
      assert_equal "ghcr.io/oknola/oknola-finance-app:oknola", svc.dig("image", "url")
      assert_equal "ohio", svc["region"]

      env = svc.fetch("envVars")
      assert_includes env, { "fromGroup" => "finance-prod" }
      assert_equal({ "name" => "finance-db", "property" => "connectionString" },
        env.find { |e| e["key"] == "DATABASE_URL" }&.dig("fromDatabase"))
      assert_equal({ "type" => "keyvalue", "name" => "finance-kv", "property" => "connectionString" },
        env.find { |e| e["key"] == "REDIS_URL" }&.dig("fromService"))
    end

    assert_equal "web", service("finance-web")["type"]
    assert_equal "/up", service("finance-web")["healthCheckPath"]
    assert_equal "worker", service("finance-worker")["type"]
    assert_equal "bundle exec sidekiq", service("finance-worker")["dockerCommand"]

    kv = service("finance-kv")
    assert_equal "keyvalue", kv["type"]
    assert_equal [], kv["ipAllowList"]

    db = BLUEPRINT.fetch("databases").find { |d| d["name"] == "finance-db" }
    assert_equal "16", db["postgresMajorVersion"]
    assert_equal "ohio", db["region"]
  end

  test "the env group carries the settings production boot and branding rely on" do
    group = BLUEPRINT.fetch("envVarGroups").find { |g| g["name"] == "finance-prod" }
    values = group.fetch("envVars").to_h { |e| [ e["key"], e["value"] ] }

    assert_equal "false", values["POSTHOG_FEEDBACK_ENABLED"]
    assert_equal "Finance", values["PRODUCT_NAME"]
    assert_equal "finance.oknola.com", values["APP_DOMAIN"]
    assert_equal "anthropic", values["LLM_PROVIDER"]
    assert_equal "link_only", values["AUTH_JIT_MODE"]
    assert_equal "https://oknola.com/terms", values["LEGAL_TERMS_URL"]
    assert_equal "https://oknola.com/privacy", values["LEGAL_PRIVACY_URL"]
    assert_not values.key?("ONBOARDING_STATE"), "the sign-up switches are typed per deploy, not synced"
    assert_not values.key?("AUTH_LOCAL_LOGIN_ENABLED"), "the sign-up switches are typed per deploy, not synced"
  end

  private
    def services
      BLUEPRINT.fetch("services")
    end

    def service(name)
      services.find { |svc| svc["name"] == name } || flunk("no service #{name} in render.yaml")
    end

    def prompted_keys(svc)
      svc.fetch("envVars").select { |e| e["sync"] == false }.map { |e| e["key"] }
    end

    def all_env_entries
      services.flat_map { |svc| svc.fetch("envVars", []) } +
        BLUEPRINT.fetch("envVarGroups").flat_map { |group| group.fetch("envVars") }
    end
end
