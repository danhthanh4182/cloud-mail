# Implementation ledger — plan: specs/001-native-mail/plan.md

Baseline: a536e30b08f698dad59b112561d2c51ca5719bd1.
User approved implementation on 2026-11-19. Worktree codex/native-implementation.
T001: complete — user approved design, scope and test seams.
Pre-flight: repository adapters shared by session/list/compose; additive API preserves legacy raw Authorization and envelope; encrypted cache scoped by server/user; server sends reconcile unknown outcomes.
Ruling: implement inline with an independent ChatGPT web architecture review plus a fresh code reviewer at the end. Chat web receives only a generic public architecture description, no secrets or user emails.
Ruling: no production credentials available; provisioned push delivery and physical-device acceptance stay explicit external readiness checks.

T002–T008 checkpoint: native app source is implemented, analysis clean. Domain/API/session tests were observed RED before core implementation; 14 Flutter tests now pass. Worker OTP/owned state/send-intent tests were observed RED→GREEN; 84 unit + 2 Cloudflare runtime tests pass. Migration was not applied to production.
Shared OTP integration: deterministic source code avoids model calls; fallback must exist verbatim in source. Two regression tests observed RED→GREEN.
Independent web architecture review: https://chatgpt.com/uc/6afdedd8-560c-83ea-82c4-7fc0bf77b12e . Accepted guidance: session generation guards; independent paging/version cursors; ambiguous send reconciliation; envelope errors; bounded attachments. No private mail/code was submitted.
Ruling: app ID dev.danhthanh.cloudmail.nativeapp keeps the native client separate from the previous wrapper. Cost: existing wrapper session does not migrate; sign-in is required.
Ruling: CI creates debug test-signed artifacts while production signing is unconfigured. Cost: clean runners may produce different test signatures, so this is not an in-place production upgrade channel.
Pending: main native journeys/device evidence, rich HTML fidelity, sync/threading, assistant rules/search and FCM push. Do not mark T009–T012 complete on an APK compile alone.

## Fresh whole-branch review and one fix pass
Reviewer `/root/native_final_review` reviewed the original implementation vs baseline with a fresh context. It did not execute suites or inspect an APK; it explicitly declined to judge subsequent fixes and hardware behavior. All reported Critical/Important findings entered this fix pass:

- Provider result shape: together mode returns saved email array, not sentRecipients. Regression observed rejected→accepted RED→GREEN using the actual adapter shape. Unknown/empty provider result remains unknown; never invite a new-key retry.
- Identity races: send captures client/generation before draft persistence; reconciliation, capabilities, restored drafts, assistant and read completion reject stale sessions. Two identity race tests observed RED→GREEN. Session deletion is serialized with persistence.
- Restore validates authenticated identity before any network inbox fetch/cache write. Regression verifies zero mail requests on mismatch and ready=true after logout.
- Interrupted before request: definitive missing intent allows explicit immutable same-key replay; editor stays locked. Recovery test first failed with missing method, then passes against 404→same-key accepted. Partial sends stay locked for reconciliation.
- Legacy organization navigation is gated and controller refuses unsupported folders. Migrated Trash/Archive/Starred include owned sent mail; route regressions observed RED→GREEN and foreign attachment access remains 404.
- Assistant masks labeled passwords/tokens, JWTs, API keys, codes and URLs; rejects credential/link output. Source evidence is mandatory. Redaction cannot prove an arbitrary secret is absent; explicit summary consent and original-source verification remain necessary.
- Migration readiness checks every required mobile table, not only one. Partial-schema test observed RED→GREEN.
- Layout regression exposed overflow at 360px / 200%; flexible branding and compact OTP fix it. Six width/scale cases now pass.

Verification after fixes: Flutter analyze clean; 26 Flutter tests pass including six native layout combinations and real-widget preview capture. Worker 91 unit + 2 Cloudflare runtime tests pass. Five harness behavioral tests pass. No reviewer minors were reported. No production email or migration ran.
Native previews render real Flutter widgets with fictional fixtures, not an installed-device screenshot. APK/device behavior still requires acceptance. CI first build completed its APK/signature/upload steps; the corrected commit will rebuild before distribution.

Final verification expansion: native widget journey login→read→reply→explicit confirmation→send passes with an isolated API fixture. The fixture asserts no send before confirmation, exactly one request carrying a stable key, correct reply reference/recipient, and durable draft removal after acceptance. This is not a live-provider or installed-device test. Actual Cloudflare D1 runtime now verifies atomic version/read/folder updates, stale-version rejection, cross-user denial, event count, and repeatable migration. Final totals: 27 Flutter tests, 91 Worker unit tests, 3 Worker runtime tests. APK workflow is PR/manual only to avoid duplicate branch-push and PR builds.

## Android 0.3 completion pass

See [AC19–AC27](../specs/001-native-mail/completion-acceptance.md) and the ordered `002_mobile_completion.sql` migration. Implemented mailbox-scoped threaded reader, native HTML tables and opt-in images, transferable owned attachments, versioned text-draft replication, persistent offline state edits, sender rules and assistant, and opt-in Firebase through an Android registration renewal job. The separate release-candidate workflow requires a configured certificate.

Independent review identified clean replica duplicates, deletion during draft upload, table image consent, HTML-only content search, last-sync persistence, inline conversation loads and background FCM token lifecycle. Fixes and evidence are linked through the completion matrix. Cloud production migration and use of a real device/provider remain pending.
