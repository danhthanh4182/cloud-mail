# Security hardening report

Branch: `chore/security-hardening` from `a792cdc` (13 commits).
Harness: `pnpm --prefix mail-worker test` → 17 files / 47 tests, twice
identical; `test:worker` → 2 files / 2 tests; `pnpm --prefix mail-vue build`
→ success, output in `mail-worker/dist`.

## Task rows

| Task | Status | Commit | Tests | Before → After | Residual risk · Rollback |
|---|---|---|---|---|---|
| Q1 test harness | done | `be14dc4` | `test/unit/req-utils.test.js` (new), `test/worker/security-middleware.test.js` (new); deleted `test/index.spec.js` | `test` was `wrangler deploy` → now `vitest run`; worker pool verified working, no fallback needed | Worker pool needs workerd download on first run (~25s). Rollback: revert `be14dc4`. |
| S1 addUser SQLi | done | `3cfd826` | `test/unit/public-add-user.test.js` (new, 3 tests) | Interpolated `VALUES ('${email}'...)` → `?` + `.bind(...)`; UPDATE untouched | drizzle-orm identifier advisory remains (see D1). Rollback: revert `3cfd826`. |
| S2 served objects | done | `de3b7ea` | `test/unit/object-response.test.js` + `test/unit/att-disposition.test.js` (new, 8 tests) | `text/html` + `inline` → `application/octet-stream` + `attachment`, `nosniff`, `sandbox; default-src 'none'`; allowlisted `image/png`/`image/svg+xml` keep type with rebuilt disposition (live `curl -I` below) | `Cache-Control: null` junk header on KV/R2/S3 branches is pre-existing and untouched. Rollback: revert `de3b7ea`. |
| S3 Resend webhooks | done | `19d69ff` | `test/unit/resend-webhook.test.js` (new, 6 tests incl. Svix known vector) | Unsigned POST accepted → Svix `v1,` HMAC-SHA256 verified, ±300s, fail closed; no secret → one warn + old behavior; errors → `unauthorized`/`bad request`/`error` with no leak | Unset `resend_webhook_secret` = verification disabled (warns). Rollback: revert `19d69ff`. |
| S4 PBKDF2 | done | `0ea319e` | `test/unit/crypto-utils.test.js` + `test/unit/login-password-upgrade.test.js` (new, 6 tests) | SHA-256(salt+password) → `pbkdf2-sha256$100000$…`; legacy verifies + lazy `resetPassword` upgrade; `genRandomPwd` 16 chars via rejection sampling; `===` → constant-time compare | 100000 = workerd default cap (`DEFAULT_MAX_PBKDF2_ITERATIONS`); larger raises `NotSupportedError`. Rollback: revert `0ea319e` (old hashes keep working — new code reads both). |
| S5 login throttle | done | `21fce57` | `test/unit/login-rate-limit.test.js` (new, 4 tests) | `notExistUser` vs `IncorrectPwd` split → uniform `IncorrectPwd`; 10 fails / 15 min → 429 `tooManyLoginAttempts` (key `login-fail:<sha256(email:ip)>`); success clears counter | In-app KV counter only — no edge rate limiting (owner action below). Rollback: revert `21fce57`. |
| S6 init/paths | done | `ae8d603` | `init-secret`, `path-match`, `telegram-token`, `escape-html` unit + `security-exclude` worker test (new, 7 tests) | GET `/init/:secret` only → POST `/init` + `X-Init-Secret` (GET kept, deprecated, warns without value); `startsWith` → `matchesPathPrefix` (`/testfoo` no longer bypasses auth); telegram JWTs carry `aud:'tg-view'` (7d); telegram page `private, no-store`; `escapeHtml` escapes `&` first; `/test` route + `test-api.js` deleted; deploy uses header init | Old GET path still active (deprecated). Rollback: revert `ae8d603`. |
| S7 session cache | done | `628c8ee` | `test/unit/login-session-profile.test.js` (new, 2 tests) | `authInfo.user = userRow` (password+salt in KV) → destructured `safeUser`; legacy entries rewritten on next login | Sessions issued before this change keep credentials until the user logs in again. Rollback: revert `628c8ee`. |
| R1 robustness | done | `38c7034` | `scheduled-jobs`, `email-ingest`, `blacklist`, `hono-onerror` (new, 7 tests) | Cron fan-out → `runScheduledJobs` (per-job try/catch); `TextDecoder` chunk loop → `parseRawEmail` (ArrayBuffer); `from.address` crash → `?.`; blacklist set/get normalized; unknown 500s → `Internal error (<id>)` with id correlation | `*/30 * * * *` branch deleted (no such trigger exists in any wrangler config). Rollback: revert `38c7034`. |
| D1 deps | done | `0e564ee` | req-utils tests guard the ua-parser downgrade | Audit prod: worker critical 1→0, high 38→2, moderate 63→26, low 19→5; vue high 26→12, moderate 21→4, low 3→2, critical 0→0. `ua-parser-js` 2.0.3 (AGPL) → 1.0.41 (MIT); `axios` 1.15.2 → 1.21.1; `lodash-es` → 4.18.1; `path` + `@cloudflare/vite-plugin` removed; `fast-xml-parser` → 5.12.1 via workspace override. License gates pass in both packages (no AGPL/GPL). | Residual highs: `drizzle-orm` SQL-identifiers (build-time; runtime uses `.bind`), `hono` CORS origin reflection, `vue-i18n` srcdoc XSS chains, `postcss`/`source-map-js`/`nanoid`/`defu`/`lodash` (transitive/dev-chain). `pnpm.overrides` in package.json is ignored by pnpm v12 — override lives in `mail-worker/pnpm-workspace.yaml`. Rollback: revert `0e564ee`. |
| D2 secrets | done | `6dc93e7` | dev smoke (below) | `jwt_secret` removed from `wrangler-dev.toml`, test value replaced with `test-only-change-me`; `.dev.vars` (ignored) + `.dev.vars.example` added; `.dev.vars` holds the dev secret | Committed `database_id`/KV `id` values are identifiers, not credentials, but listed for the owner below. Rollback: revert `6dc93e7`. |
| D3 workflow/CI | done | `8f5aa41` | YAML-parsed; CI runs on PR (pending, see push) | Workflow `permissions: contents read / actions write`; API token/account-id/JWT moved job→step env (Cloudflare checks relocated to the KV step, first consumer); JWT validation also rejects `\| & "`; `delete-workflow-runs` pinned to `6c7cf48`; new `ci.yml` (install/build/test/audit/license gates) + `dependabot.yml` (weekly) | CI has not run yet (no PR runs on a fresh branch until pushed). Rollback: revert `8f5aa41`. |

## Verification evidence

- Unit suite twice: `Test Files 17 passed (17), Tests 47 passed (47)` ×2.
- Worker suite: `Test Files 2 passed (2), Tests 2 passed (2)`.
- Injection gates: `VALUES ('${` → none; `Math.random` in src → none;
  `jwt_secret *= "[A-Za-z0-9-]{20,}"` in `mail-worker/*.toml` → none;
  `@main` in workflows → none; `api/init/` under `.github/` → none.
- Dev smoke: `POST /api/init` → `success`; `/api/login` →
  `{"code":501,"message":"密码输入错误"}`; deprecated `GET /api/init/:secret`
  → `success` (warn in log, value-free).
- S2 live headers (`/static/probe.*` seeded in local KV):
  - html → `content-type: application/octet-stream`,
    `content-disposition: attachment; filename="probe.html"; filename*=UTF-8''probe.html`,
    `x-content-type-options: nosniff`,
    `content-security-policy: sandbox; default-src 'none'`.
  - png → `content-type: image/png`,
    `content-disposition: inline; filename="probe.png"; filename*=UTF-8''probe.png`,
    same `nosniff` + CSP.

## Rulings

- S5 oauth path: missing user → `IncorrectPwd` on all paths (never
  `notExistUser`); dummy hash + failure recording skipped when
  `noVerifyPwd` (avoids hashing a null password). No caller depends on
  the distinction (verified in `oauth-service.js`). Cost if wrong: an
  inconsistent oauth state reports a password error.
- S2 test asserts the full original `Content-Type` (`image/png;
  charset=binary`) is preserved for allowlisted types — "preserved" means
  not forced to `octet-stream`, not normalized.
- D1: pnpm v12 ignores the `pnpm` field in package.json — the
  `fast-xml-parser` override lives in `mail-worker/pnpm-workspace.yaml`.
- D3: `CLOUDFLARE_*` presence checks moved from "Set up environment" to
  "Set up KV database" (first consumer) because the vars are now
  step-scoped. Misconfigured creds fail one step later, same outcome.
- S4 verify parses the stored iteration count (future bumps stay
  verifiable); well-formed new hashes never rehash.

## Manual actions for the repo owner

1. Rotate `jwt_secret` if either deployed environment ever used the
   previously committed value (invalidates sessions).
   - `wrangler-dev.toml` used `database_id a4c1a63a-6ef5-4e6d-8e8c-b6d9e8feb810`,
     KV id `2io01d4b299e481b9de060ece9e7785c` (local bindings).
   - `wrangler-test.toml` uses `database_id e65f099d-796d-4eaa-8dff-529b368b20db`,
     KV id `9be10cd058e04c55b526f8c0c116f50c`; test secret is now the
     literal `test-only-change-me`.
2. Set `resend_webhook_secret` (`whsec_...`) in the deployed environment;
   until set, webhook verification is disabled (one warn per isolate).
3. Add a Cloudflare Rate Limiting rule for `/api/login` (and
   `/api/register`) — the in-app KV counter is per-instance best-effort.
4. GitHub Actions vars/secrets: none renamed (`JWT_SECRET`,
   `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` unchanged); no updates
   needed beyond normal rotation.

## Deployment repair — 2026-11-17

- Root cause: two pipelines deployed the same `cloud-mail` Worker for each
  `main` push. GitHub Actions deployed the application at 14:04:31 UTC;
  Cloudflare Workers Builds replaced it with an assets-only deployment at
  14:04:40 UTC, before database initialization at 14:04:49 UTC.
- The replacement had no fetch/email/scheduled handlers or DB/KV bindings,
  and served `mail-vue/index.html` with `/src/main.js` instead of the Vite
  release bundle. This caused both `POST /api/init` HTTP 404 and the
  browser's unresolved bare `vue` import.
- GitHub Actions is the sole production deploy pipeline. The duplicate
  Workers Builds trigger was removed from this Worker's Build settings;
  no Worker, database, namespace, or email data was removed. Do not
  reconnect production auto-builds while Actions deploys the same Worker.
- The workflow now serializes production runs without cancelling an
  in-progress deploy, triggers on changes to its own configuration, and
  preserves Wrangler's exit status under explicit Bash `pipefail`.
- Regression coverage executes the real deploy step with only the remote
  Wrangler command substituted: failed deployments must fail the job and
  publish no URL; successful deployments publish the workers.dev URL.
- Recovery: merge the workflow repair or run `deploy-cloudflare.yml`
  through Actions. It uses `mail-worker/wrangler-action.toml`, builds Vue
  into `mail-worker/dist`, deploys the Worker and bindings together, then
  initializes the database. Verify Actions completes, the home page uses
  `/assets/*.js` rather than `/src/main.js`, and the API is reachable.
- Rollback: revert the workflow change if needed, but do not restore the
  old root-directory Workers Builds command (`npx wrangler deploy` with
  no build command): it would overwrite the application again. Migrating
  to Workers Builds requires the complete Worker config, release build,
  bindings, and secrets before switching deployment ownership.

## Analytics tooltip and dependency updates — 2026-11-17

- Sender chart tooltips render names as text nodes, preventing stored HTML
  from being interpreted as markup. Regression tests cover malicious names
  and ordinary names containing HTML-significant characters.
- Worker and frontend dependencies were updated; full `pnpm audit --json`
  reported no advisories in either lockfile at the time of verification.
- The Worker test harness uses `@cloudflare/vitest-plugin`; its Worker module
  is loaded before request tests so first-load compilation does not consume
  the request timeout. The plugin currently pins a beta Miniflare build.
- Workbox's `glob` dependency is overridden to version 14 to pick up security
  fixes; its manifest generation was checked with nested and ignored files.
  Revisit the override when Workbox supports a patched version directly.
