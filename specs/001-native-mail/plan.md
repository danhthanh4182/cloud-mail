# Cloud Mail Native Implementation Plan

**Branch:** `001-native-mail` · **Date:** 2026-11-18 · **Spec:** [spec.md](spec.md)  
**Status:** Approved for implementation on 2026-11-19. Execution/evidence: `docs/implementation-ledger.md`.

**Goal:** Native Android email application satisfying US01–US08, with honest milestones and Actions-only binaries.
**Architecture:** Flutter presentation and Material 3 design system; feature modules expose repository interfaces to typed legacy/mobile API adapters. A sync coordinator owns encrypted cache and optimistic mutations. Worker extensions preserve web/Telegram APIs and add capabilities, owned state, AI jobs and push.
**Stack:** Flutter stable/Dart with committed SDK pin and lockfile, Material 3, repository/state-management module, HTTPS client, encrypted database + platform keystore. Exact dependency versions are selected and vulnerability/license checked at T002; no fictitious version pins in this plan.

## Global constraints
Android API floor selected after resolving plugin minimums, target current supported SDK verified from official SDK at implementation. Proposed minimum Android 8/API26, target at least API35. No app WebView. No build output/signing keys in Git. No production data required for tests. VI/EN, light/dark, text scaling 200%, 48dp touch minimum. Preserve baseline code=200 envelope, raw Authorization and unread convention.

## Modules
- `apps/mobile/lib/app/`: routing, capability-aware navigation, session scope, localization.
- `apps/mobile/lib/design_system/`: semantic tokens, typography, Material theme extensions and shared components.
- `apps/mobile/lib/features/{session,mailbox,reader,compose,organization,assistant,settings}/`: domain/models, repository interface, presentation.
- `apps/mobile/lib/sync/`: cursor sync, conflicts, encrypted cache and mutation queue.
- `mail-worker/src/api/mobile-api.js`, `service/mobile/`: additive API/capability/ownership boundary.
- `mail-worker/migrations/`: additive D1 state/sync/send/push schema.
- `apps/mobile/test/`, `integration_test/`; backend Vitest suites; `specs/001-native-mail/contracts/fixtures/` for shared contract fixtures.

## Review focus
1. Session changes during in-flight calls must not cross identity boundaries. Test repository/session invalidation.
2. Ambiguous send results must not trigger duplicate delivery. Test interrupted provider response and request hash mismatch.
3. HTML/malicious instructions must not execute or expose tokens. Test reader sanitizer and assistant input boundary.
4. Legacy deployment cannot pretend to support trash/labels/push. Test capability-driven UI and permission handling.
5. Offline/device restore must not erase drafts or show stale foreign data. Test cache-key isolation, tombstones and resync.

## Tracer bullet delivery and dependencies

### Milestone A: reviewed foundation
T001 inventory/spec/design/ADRs → T002 Flutter skeleton/design components → T003 typed API and contract fixtures. Build a test-signed native login/inbox shell only after approval; label it foundation, not complete.

### Milestone B: daily email client
T004 session/address management → T005 list/search/paging → T006 reader/OTP/attachments → T007 composer/drafts + T008 owned state/idempotent-send backend. Integrate send/reply/forward only after idempotency behavior is tested. Existing webmail/Telegram regression suite must pass.

### Milestone C: complete requested experience
T009 sync/offline/threading → T010 assistant/user rules → T011 push and settings → T012 end-to-end, visual/accessibility/security review and release candidate.

## Test seams to approve
Domain: OTP candidate selection, recipient parser, reply/thread relation, draft recovery and send-state machine. Repository/API: exact serialization/envelopes, permissions, paging, session isolation and sync conflicts. Presentation: main screens as widget/golden tests and user flows on Android emulator/device. Backend: owned writes, idempotency, migrations, assistant boundaries and push revoke. These are proposed TDD seams, not already-passing tests.

## Verification commands (after scaffold)
`flutter analyze`; `flutter test`; `flutter test integration_test --device-id <controlled-emulator>`; `npm --prefix mail-worker test` or repository's verified scripts; `flutter build apk --debug` for test artifact; `flutter build appbundle --release` only with configured release signing. Record exact actual commands/versions and results in release evidence.

## Constitution check
Requirement traceability and status are present; new API is separated from existing; artifacts remain external; privacy/integrity/a11y risks have tasks. Pending release gates: Flutter/backend tests; credentials/config for live push; representative-device evidence; production signing. Do not turn pending gates into green checkmarks.
