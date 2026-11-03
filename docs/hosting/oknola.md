# Running finance.oknola.com (Oknola Finance App on Render)

The runbook for Cardona Labs' production instance of the Oknola Finance App, a fork of Sure. The generic self-hosting guides in this folder still apply; this page covers what is specific to this instance.

> **Sign-up order. Do this exactly once, in this order, before anyone uses the Oknola handoff.**
>
> 1. First apply the Blueprint with `ONBOARDING_STATE=open` and `AUTH_LOCAL_LOGIN_ENABLED=true` on `finance-web`.
> 2. Register the ops account at `https://finance.oknola.com/registration/new`. The first registered user becomes `super_admin`.
> 3. Turn on MFA for it (Settings → Security: TOTP or a passkey) and store the backup codes in the password manager.
> 4. On `finance-web` → Environment, set `ONBOARDING_STATE=closed` and `AUTH_LOCAL_LOGIN_ENABLED=false`, then save (Render redeploys).
> 5. Check `/settings/hosting` shows onboarding **closed** and `/admin/system_health` is green.
>
> Only then may the Oknola server create users through the handoff. If a handoff user existed first, it would be the `super_admin`. The env var is only the default: if `/settings/hosting` still shows "open" after step 4 (someone saved that page earlier), set it to "closed" there.

## What runs where

All in the Render workspace "Cardona Labs", region Ohio, from `render.yaml` at the root of the `oknola` branch.

| Resource | Render name | What it is |
|---|---|---|
| Web service | `finance-web` | Image `ghcr.io/oknola/oknola-finance-app`, Puma. Runs `db:prepare` (migrations) on every boot. Custom domain `finance.oknola.com`, health check `/up`. |
| Background worker | `finance-worker` | Same image, `bundle exec sidekiq`. |
| Postgres 16 | `finance-db` | Render's daily backups plus the weekly off-site copy below. |
| Key Value | `finance-kv` | Sidekiq queues, Action Cable and `Rails.cache` (the one-time handoff codes). Internal connections only, `noeviction`. |
| Env group | `finance-prod` | Every plain (non-secret) setting. Both services read it. |

Production refuses to boot unless all three `ACTIVE_RECORD_ENCRYPTION_*` values are set, `POSTHOG_FEEDBACK_ENABLED=false` and `REDIS_URL` is set (`config/initializers/oknola.rb`). A deploy that fails with "Oknola production configuration incomplete" names what is missing.

## Secrets

Render does not allow prompted (`sync: false`) values inside an environment group, so secrets live on each service. **`finance-web` and `finance-worker` must hold the same value for every secret they share**: a mismatched encryption key makes the worker unable to read what the web wrote. Keep the master copy of every value in the password manager.

| Name | `finance-web` | `finance-worker` | Generate |
|---|---|---|---|
| `SECRET_KEY_BASE` | yes | yes | `openssl rand -hex 64` |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | yes | yes | `openssl rand -hex 32` |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | yes | yes | `openssl rand -hex 32` |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | yes | yes | `openssl rand -hex 32` |
| `OKNOLA_HANDOFF_SECRET` | yes | no | `openssl rand -hex 32`; the same value goes into the Supabase Edge Function secrets |
| `ANTHROPIC_API_KEY` | yes | yes | console.anthropic.com, key "finance-prod" |
| `SENTRY_DSN` (optional) | yes | yes | sentry.io project "finance" |
| `SMTP_PASSWORD`, `EMAIL_SENDER` (optional) | yes | yes | Resend key "finance-smtp"; the sender address |
| `ONBOARDING_STATE`, `AUTH_LOCAL_LOGIN_ENABLED` | yes | no | see the sign-up order above |

Render prompts for these only on the first Blueprint apply. A secret added later goes in by hand on each service (Render ignores `sync: false` entries on later syncs and keeps values set in the dashboard).

GitHub repository secrets (Settings → Secrets and variables → Actions):

- `RENDER_WEB_DEPLOY_HOOK_URL`, `RENDER_WORKER_DEPLOY_HOOK_URL`: from each service's Settings → Deploy Hook. Treat them as secrets: anyone holding one can redeploy.
- `DATABASE_URL`: `finance-db` → Connect → External Database URL, for the off-site backup.
- `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`: a private Cloudflare R2 bucket and an API token limited to it (Object Read & Write). Add a lifecycle rule on the bucket to delete objects after 90 days.

## Deploys

Every push to `oknola` runs `.github/workflows/publish-oknola.yml`: the full CI suite, then an amd64 image build tagged `sha-<commit>` and `oknola`, then the web deploy hook pinned to `sha-<commit>`, a wait for `/up`, then the worker hook. Until both hook secrets exist the deploy job only prints a notice. Pushes that change only docs or Markdown skip the workflow.

After the very first image push, make the package public once: github.com/orgs/Oknola/packages → `oknola-finance-app` → Package settings → Change visibility → Public. Render pulls it without a registry credential.

Roll back: Render → `finance-web` → Events → pick the previous deploy → Rollback, then the same on `finance-worker`. Migrations are not reversed by a rollback; restore the database (below) if a migration damaged data.

## Upgrade to a new upstream release

The `oknola` branch is never rebased. Upstream releases arrive as merges.

1. Back up first: run the "Off-site database backup" workflow by hand (Actions → Off-site database backup → Run workflow) and wait for it to go green.
2. On a branch from `oknola`: `git fetch upstream --tags && git merge vX.Y.Z` (the next stable tag, never `main`). Resolve conflicts in favour of keeping our files and notices.
3. Run `bin/rails test` (and `bin/rails test:system`) until green; CI repeats both on the PR.
4. Two-family isolation smoke on a local copy: create two families through the handoff, add an account and a transaction in each, and check neither family can see the other's accounts, transactions, tags or reports.
5. Lookbook screenshot check: open `/design-system` locally and compare the components our screens use against the previous release.
6. Open a PR into `oknola`, review, merge. The merge deploys (see Deploys). Watch `/admin/system_health` afterwards.

## Restore

Two sources, newest first:

- **Render's own backups**: `finance-db` → Recovery. Point-in-time recovery creates a new database; it does not overwrite the old one. Point the services at the new database (each service → Environment → `DATABASE_URL`, or rename in the Blueprint), redeploy, check, then delete the old instance.
- **The off-site copy** (when Render itself is the problem): download the newest `finance-db/*.dump` from the R2 bucket, then into an empty Postgres 16:

  ```bash
  pg_restore --no-owner --no-privileges --dbname="$NEW_DATABASE_URL" finance.dump
  ```

A restore is only readable with the same three `ACTIVE_RECORD_ENCRYPTION_*` values that wrote it (bank tokens and API keys are encrypted columns) and the same `SECRET_KEY_BASE` (instance-wide API keys in Settings are encrypted with it). Losing those values loses those columns; keep them in the password manager next to the backup notes.

## Key rotation

Rotate on suspected exposure (that is also an incident, below), never on a schedule. The keys are independent: rotating one does not require rotating the others. If the whole environment leaked, rotate all of them.

**`SECRET_KEY_BASE`.** It signs sessions and cookies and, through `Setting`'s encryptor (`app/models/setting.rb`), encrypts the instance-wide API keys saved in Settings → Hosting. It does not touch Active Record encryption, because the three `ACTIVE_RECORD_ENCRYPTION_*` values are set explicitly. Steps:

1. Note which instance-wide keys are saved in Settings → Hosting (market data, AI provider tokens). After rotation they cannot be decrypted, and `Setting` returns the raw ciphertext without an error, so they must be re-entered.
2. Set the new value on both services at once and redeploy both. Every user is signed out; Oknola users get a new session on their next handoff.
3. Re-enter the keys from step 1 in Settings → Hosting, and check `/admin/system_health`.

**`ACTIVE_RECORD_ENCRYPTION_*`.** These encrypt bank-provider tokens, provider payloads, invitation tokens and emails. Rails can read with old keys while writing with new ones, but `config/initializers/active_record_encryption.rb` takes one value per key from the environment, so rotation is a code change, rehearsed on a restored copy before production:

1. In a PR, let the initializer also read the old values (for example `ACTIVE_RECORD_ENCRYPTION_PREVIOUS_*`).
   - Primary key only: `primary_key` becomes `[old, new]`; Rails tries every key to decrypt and encrypts with the last.
   - Deterministic key or salt: Rails does not rotate these in place (its guide: key rotation is not supported for deterministic encryption, and the salt feeds every derived key). Add the old values as a previous scheme, `config.active_record.encryption.previous = [{ key_provider: <a provider built from the old key and old salt> }]`, and set `config.active_record.encryption.extend_queries = true` so lookups on deterministic columns (invitation tokens and emails, provider API keys) still match old rows. See "Previous encryption schemes" in the Rails Active Record Encryption guide.
2. Deploy with both old and new values on both services.
3. Re-encrypt every row: `bin/rails runner 'Rails.application.eager_load!; ActiveRecord::Base.descendants.select { |m| m.encrypted_attributes.present? && !m.abstract_class? }.each { |m| m.find_each(&:encrypt) }'` (Render → `finance-worker` → Shell).
4. Check a few rows read back, then remove the old values and the previous scheme in a second PR.

There is no `bin/rails db:encryption` re-encrypt task; `bin/rails db:encryption:init` only prints new keys.

**`OKNOLA_HANDOFF_SECRET`.** Set the new value in Supabase (Edge Function secrets) and on `finance-web` within the same minute; handoffs fail with 401 in between.

**`ANTHROPIC_API_KEY`, `SMTP_PASSWORD`, `SENTRY_DSN`, deploy hooks, R2 token.** Create the new one, set it on both services (or in GitHub secrets), redeploy, then revoke the old one at the provider. A deploy hook is regenerated in the service's Settings.

## Incident

Any suspected exposure of `SECRET_KEY_BASE`, the encryption keys, Plaid secrets or the database is a lawyer-first event, and the owner is told within 24 hours.

1. Write down what is known, when it was found, by whom. Keep times in UTC.
2. Tell the owner within 24 hours of the discovery, even when the facts are incomplete.
3. Contain: rotate the exposed values (Key rotation above); revoke Plaid secrets at dashboard.plaid.com if they may be exposed; set `ONBOARDING_STATE=closed` if sign-ups are involved; suspend `finance-web` in Render if data is actively leaking.
4. Keep evidence: export the Render logs for the window and do not delete the affected database (restore into a new one instead).
5. The lawyer decides on user and state notices; do not notify users before that.

### Clean up a failed Finance purge

When Oknola's account deletion logs `finance purge failed for <sub>`, remove that user's Finance data by hand. The secret is read from the terminal so it never lands in the shell history or a URL:

```bash
read -rs OKNOLA_HANDOFF_SECRET
curl --fail-with-body -X DELETE \
  -H "Authorization: Bearer ${OKNOLA_HANDOFF_SECRET}" \
  "https://finance.oknola.com/oknola/accounts/<sub>"
unset OKNOLA_HANDOFF_SECRET
```

A 204 means purged (also for a `sub` that no longer exists).

## Legal pages

`LEGAL_TERMS_URL=https://oknola.com/terms` and `LEGAL_PRIVACY_URL=https://oknola.com/privacy` are set in the `finance-prod` env group, so `/terms` and `/privacy` redirect to oknola.com (`config/routes.rb`). They show a 404 until the site's terms PR (PT3) is merged.

## Known limits

- **Memory.** The web and worker plans are 0.5 CPU / 512 MB. Upstream measures about 352 MB steady state but asks for at least 1 GB when AI features are on (`docs/hosting/docker.md`, "Running Sure on small (512 MB) hosts"). If the worker restarts with out-of-memory events, move `finance-worker` to `1c-2g`.
- **Uploaded files.** `ACTIVE_STORAGE_SERVICE` is not set, so uploads go to the container's disk, which Render wipes on every deploy. Pointing it at an R2 bucket (`cloudflare` in `config/storage.yml`) keeps them.
