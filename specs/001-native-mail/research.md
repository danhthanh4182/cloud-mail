# Discovery and alternatives

Research date 2026-11-18. Source baseline: danhthanh4182/cloud-mail @ 2763a30e574036ca206a65f1165a513b1639f3a6. Files read directly from clone, no production credentials inspected.

## Evidence
- `mail-vue/package.json`: Vue 3, Vite, Element Plus; no native mobile project on main.
- `mail-worker/src/api/login-api.js`: POST /api/login {email,password} -> {code,data:{token}}.
- `mail-vue/src/axios/index.js`: Authorization is the raw token, not an assumed Bearer prefix; errors can live in HTTP-200 envelopes.
- `mail-worker/src/service/account-service.js`: list is a raw array, paginated by sort + accountId, limit 30.
- `mail-worker/src/service/email-service.js`: list numeric type 0 receive / 1 send, size cap50, cursor emailId/timeSort, full=1 returns content/attachments. Search subject/content/sender/senderAddress/recipientAddress + dates. No dedicated user detail route was found.
- `mail-worker/src/const/entity-const.js`: unread=0 means UNREAD and unread=1 means READ.
- `mail-worker/src/service/star-service.js`: add/cancel idempotent behavior, list {list} without total.
- `mail-worker/src/service/email-service.js:delete`: syncDelete can invoke physical deletion. Do not promise undo with existing route.
- `mail-vue/src/layout/write/index.vue` + `utils/file-utils.js`: JSON attachment {content:rawBase64,filename,size,contentType}; drafts use browser IndexedDB and are not server-synced.
- `mail-worker/src/service/ai-service.js`: Workers AI extracts <=8-character unspaced codes; no source-membership validation. `telegram-service.js` already uses copy_text.
- `mail-worker/src/api/r2-api.js`: GET /api/oss/* serves attachment bytes. Production access policies/URLs must be verified before mobile downloads.

## Framework alternatives
| Option | Benefit | Cost | Decision |
|---|---|---|---|
| Flutter + Material3 | Native-rendered complete design system, typed client, widget/golden tests; potential later iOS | New client and package toolchain | Proposed |
| Kotlin + Jetpack Compose | Best direct Android platform integration | Android-only client and a second platform rewrite later | Viable alternative |
| Capacitor/WebView | Reuses Vue immediately | Fails explicit native experience requirement | Rejected |

Official Spec Kit CLI initialized the repository from github/spec-kit commit ae68a0bd0ab01dd7eec52ffad1f8faca789f96ef (CLI asset metadata 1.4.3.dev0). Core templates/scripts and Codex integration are committed; no claim that upstream CLI generates or validates product correctness automatically.

## Still unverified
Actual deployment URL/capabilities; production R2 access policy; auth variants used by this account; rate limits in production; Firebase push credentials; representative-device performance; existing backend data migration safety. These are readiness checks, not invented facts.
