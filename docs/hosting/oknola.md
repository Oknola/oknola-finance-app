<!-- Modified by Cardona Labs, LLC, 2026-11-03, AGPL-3.0 -->
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
| R2 bucket (Cloudflare) | `oknola-finance-storage` | Active Storage: uploads, imports, exports. See Uploaded files. |

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
| `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_ACCESS_KEY_ID`, `CLOUDFLARE_SECRET_ACCESS_KEY` | yes | yes | the storage bucket's R2 token, see Uploaded files |
| `SENTRY_DSN` (optional) | yes | yes | sentry.io project "finance" |
| `SMTP_PASSWORD`, `EMAIL_SENDER` (optional) | yes | yes | Resend key "finance-smtp"; the sender address |
| `ONBOARDING_STATE`, `AUTH_LOCAL_LOGIN_ENABLED` | yes | no | see the sign-up order above |

Render prompts for these only on the first Blueprint apply. A secret added later goes in by hand on each service (Render ignores `sync: false` entries on later syncs and keeps values set in the dashboard).

GitHub repository secrets (Settings → Secrets and variables → Actions):

- `RENDER_WEB_DEPLOY_HOOK_URL`, `RENDER_WORKER_DEPLOY_HOOK_URL`: from each service's Settings → Deploy Hook. Treat them as secrets: anyone holding one can redeploy.
- `DATABASE_URL`: `finance-db` → Connect → External Database URL, for the off-site backup.
- `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`: a private Cloudflare R2 bucket and an API token limited to it (Object Read & Write). Add a lifecycle rule on the bucket to delete objects after 29 days (R2 → the bucket → Settings → Object lifecycle rules → Add rule: name `expire-dumps`, prefix `finance-db/`, "Delete uploaded objects" after 29 days). Oknola's Finance terms promise deleted data leaves backups within 30 days, and R2 may take up to a day to act on a rule; never lengthen it.

## Uploaded files

Active Storage keeps uploads, imports and exports in R2 (`ACTIVE_STORAGE_SERVICE=cloudflare` and `CLOUDFLARE_BUCKET=oknola-finance-storage` in the `finance-prod` env group; the `cloudflare` service in `config/storage.yml`). Both services must use the same bucket: the worker builds exports the web serves, and reads imports the web received. Neither service's disk survives a deploy.

Owner steps, before the first Blueprint apply:

1. Cloudflare → R2 → Create bucket `oknola-finance-storage`. Keep it private (no public access, no custom domain). This is a separate bucket from the off-site backup one.
2. R2 → Manage API tokens → Create API token: permission **Object Read & Write**, applied to `oknola-finance-storage` only. Do not reuse the backup token, and do not give this token access to the backup bucket.
3. Paste on **both** `finance-web` and `finance-worker` (the first Blueprint apply prompts for them; later, each service → Environment), the same values on both:
   - `CLOUDFLARE_ACCOUNT_ID`: the account id shown on the R2 overview page.
   - `CLOUDFLARE_ACCESS_KEY_ID`, `CLOUDFLARE_SECRET_ACCESS_KEY`: the token's Access Key ID and Secret Access Key (shown once; keep them in the password manager).
4. If the bucket gets another name, change `CLOUDFLARE_BUCKET` in the `finance-prod` env group.

No CORS rule is needed: the app's screens upload through the app server (no Active Storage direct uploads in the UI), and downloads are redirects to short-lived signed R2 links, which a browser follows without CORS. If a screen ever adds direct uploads, add a CORS rule on the bucket allowing `PUT` from `https://finance.oknola.com` with the `Content-Type`, `Content-MD5` and `Content-Disposition` headers.

The database backups do not include these files.

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
2. Note the SSO identity blocks listed on `/admin/users` (identities a super admin removed). Each block matches by an HMAC digest keyed from `SECRET_KEY_BASE` (`app/models/sso_identity_block.rb`); after rotation no block matches, so a removed identity can come back through the handoff. Only the digest is stored, so the blocks cannot be recomputed: watch for those people returning and deactivate them again (that writes new blocks).
3. Set the new value on both services at once and redeploy both. Every user is signed out; Oknola users get a new session on their next handoff. Also invalidated: every subscribed bill-calendar feed URL (signed by `Rails.application.message_verifier("bills-user-feed")`; members copy the link again from Bills → calendar) and any unused password-reset or email-confirmation link.
4. Re-enter the keys from step 1 in Settings → Hosting, and check `/admin/system_health`.

**`ACTIVE_RECORD_ENCRYPTION_*`.** These encrypt bank-provider tokens, provider payloads, invitation tokens and emails. `config/initializers/active_record_encryption.rb` takes one value per key from the environment, so any rotation is a code change, rehearsed on a restored copy before production. The three values do not rotate the same way (Rails 8.1, checked against `activerecord` 8.1.3.1):

- **Primary key: rotate.** In a PR, let the initializer also read the old value (for example `ACTIVE_RECORD_ENCRYPTION_PREVIOUS_PRIMARY_KEY`) and set `primary_key` to `[old, new]`. Rails tries every key to decrypt and encrypts with the last.
  1. Deploy with both values on both services.
  2. Re-encrypt every row: `bin/rails runner 'Rails.application.eager_load!; ActiveRecord::Base.descendants.select { |m| m.encrypted_attributes.present? && !m.abstract_class? }.each { |m| m.find_each(&:encrypt) }'` (Render → `finance-worker` → Shell). This rewrites the non-deterministic columns under the new key; it leaves the deterministic ones as they are (they use the deterministic key, not the primary key).
  3. Before a second PR drops the old value, prove it on a restored copy (below).
- **Deterministic key: do not rotate in place.** Rails refuses more than one deterministic key ("Deterministic encryption keys can't be rotated"). The only way to keep reading old rows is a previous scheme (`config.active_record.encryption.previous = [{ key_provider: ActiveRecord::Encryption::DeterministicKeyProvider.new(old_key) }]` with `extend_queries = true`), and while any previous scheme exists Rails writes every deterministic attribute with the **oldest** scheme (`EncryptedAttributeType#serialize_with_oldest?`). So the re-encrypt pass above, and every normal save, keeps those columns under the old key: `users.email` and `users.otp_secret` (sign-in itself), the bank-provider `api_key` / `token` / `access_token` / `session_id` columns (for example `plaid_items.access_token`), `api_keys.display_key`, invitation tokens and emails (`grep -rn 'deterministic: true' app/models` lists them all). Removing the previous scheme afterwards makes them unreadable. If the old deterministic key is exposed, keep it as a permanent previous scheme, or move the data with a separately reviewed script that decrypts with the old key and writes new ciphertext with `update_columns`, rehearsed on a restored copy.
- **Key derivation salt: do not rotate in place.** It is one global value that derives both the primary and the deterministic keys (`ActiveRecord::Encryption::KeyGenerator#derive_key_from`), and a previous scheme cannot carry its own salt. Keep the old salt. Changing it needs the same reviewed migration script as the deterministic key.

**Never remove an old key or a previous scheme** until a console on a **restored copy** of production (Restore above), running the build with the old value or scheme removed, reads every encrypted column of every model: for example `bin/rails runner 'Rails.application.eager_load!; ActiveRecord::Base.descendants.select { |m| m.encrypted_attributes.present? && !m.abstract_class? }.each { |m| m.find_each { |r| m.encrypted_attributes.each { |a| r.public_send(a) } } }'` finishing without an `ActiveRecord::Encryption::Errors::Decryption`. Run it with `ACTIVE_RECORD_ENCRYPTION_SUPPORT_UNENCRYPTED_DATA` unset: with it on, Rails returns an unreadable value as its raw ciphertext instead of raising, and the check passes falsely.

There is no `bin/rails db:encryption` re-encrypt task; `bin/rails db:encryption:init` only prints new keys.

**`OKNOLA_HANDOFF_SECRET`.** Set the new value in Supabase (Edge Function secrets) and on `finance-web` within the same minute; handoffs fail with 401 in between.

**`ANTHROPIC_API_KEY`, `SMTP_PASSWORD`, `SENTRY_DSN`, deploy hooks, R2 tokens (backup and storage).** Create the new one, set it on both services (or in GitHub secrets), redeploy, then revoke the old one at the provider. A deploy hook is regenerated in the service's Settings.

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
`test/controllers/oknola/legal_redirect_test.rb` proves both the redirect and the stock fallback.

## Known limits

- **Memory.** `finance-web` and `finance-worker` are both 1 CPU / 2 GB (`1c-2g`). The web started on 0.5 CPU / 512 MB and was killed for running out of memory on the first page loads; upstream measures about 352 MB steady state but asks for at least 1 GB when AI features are on (`docs/hosting/docker.md`, "Running Sure on small (512 MB) hosts"). The web runs Puma in single-process mode (`WEB_CONCURRENCY=0` in `render.yaml`), because Render's default of 1 starts a master plus one worker. The worker runs AI jobs, imports and syncs.
