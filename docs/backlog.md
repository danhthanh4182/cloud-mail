# Backlog (tickets only — not started)

1. Versioned D1 migrations instead of `init.js` — the `init()` chain is
   append-only and order-dependent; replace with a migration runner that
   records applied versions.
2. Outbound webhook HMAC + timestamp + timeout/backoff via `waitUntil` —
   `webhookService.sendEmail` currently posts without authentication or
   retry budget.
3. TinyMCE from npm instead of `mail-vue/public/tinymce` vendoring —
   removes the GPL-2.0-or-later blob from the repo and makes upgrades
   auditable.
4. `vi` locale + key-parity check — add a unit test asserting `en.js` and
   `zh.js` (and any new locale) export identical key sets so new strings
   like `tooManyLoginAttempts` can't ship half-translated.
5. `// @ts-check`/JSDoc or TypeScript migration for `mail-worker` —
   several steps here were saved by tests that types would have caught at
   edit time.
6. Cloudflare edge rate limiting for `/api/login` and `/api/register` —
   the in-app KV counter (S5) is per-instance best-effort; enforce at the
   edge.
