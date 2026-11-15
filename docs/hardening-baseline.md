# Security hardening baseline

Date: 2026-11-16
Base commit: `a792cdc` (main, clean)
Worktree: `D:/02_Projects/Dev/cloud-mail-security-hardening`
Branch: `chore/security-hardening`

## Toolchain

- node: v26.13.1
- pnpm: 12.16.1
- wrangler: 4.90.0

## Measurements

- `pnpm --prefix mail-vue build`: PASS. Output lands in `mail-worker/dist`
  (SPA + `sw.js`/`workbox-*.js`). Browserslist warning only
  ("update browserslist db" nag).
- `pnpm audit --prod` (exit 1 in both packages, as expected):
  - mail-worker: critical 1, high 38, moderate 63, low 19. Notable: 1×
    critical (fast-xml-parser entity-encoding bypass), high incl.
    fast-xml-parser (×3), drizzle-orm SQL injection via identifiers,
    undici (×11), nanoid (×3), hono CORS, plus dev-chain items
    (vite, rollup, sharp, postcss, source-map-js, form-data, defu,
    @fastify/busboy, ws, zod).
  - mail-vue: critical 0, high 26, moderate 21, low 3. Notable: axios
    (×12, incl. credential leak + proxy bypass + ReDoS), lodash-es
    code injection via `_.template`, vue-i18n XSS chains, defu,
    form-data, postcss, source-map-js, nanoid.
- `pnpm --prefix mail-worker test`: NOT RUN — the script is currently
  `wrangler deploy --config wrangler-test.toml` (deploys to the test
  account). Replaced with vitest in Step 1 (Q1).
- Lockfile churn from `pnpm install`: none (`git status` clean apart
  from this doc).

## Dev smoke (wrangler dev, local bindings)

- `GET /api/init/<secret>` → `success` (note: `wrangler-dev.toml` uses
  CRLF line endings; naive `sed` capture keeps the trailing `\r` and the
  init check rejects it — strip `\r` when extracting).
- `POST /api/login` `{"email":"admin@example.com","password":"x"}` →
  `{"code":500,"message":"D1_ERROR: no such table: user: SQLITE_ERROR"}`
  (numeric `code` in a JSON envelope — error handling path works against
  an un-migrated local D1).

No secret values are recorded in this document.
