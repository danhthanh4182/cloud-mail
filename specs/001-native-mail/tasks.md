# Tasks · 001-native-mail

All implementation tasks are TODO. T001 documentation is prepared but awaits product/design review. Every task ends with implementation evidence and Standards + Spec review. Do not check a task merely because its file exists.

| ID | Task / deliverable | Blocks on | Requirements | Acceptance evidence |
|---|---|---|---|---|
| T001 | Source inventory, constitution, spec/ADRs, flow, mockup, design system and test plan | none | all | User design review; local links/schema checks; two-axis doc review |
| T002 | Flutter skeleton, version pins, theme/l10n/components and CI analysis/test | T001 approval | FR16/17 | Golden light/dark components at 360/412/840; text scale200%; no binary/key in tree |
| T003 | Typed discovered + proposed API contract schemas/fixtures, error taxonomy | T001 approval | FR01/02/03/06/09 | RED→GREEN envelope/HTML error/401/403/raw-token/unread tests |
| T004 | Secure login/session/address/profile/password flows | T002,T003 | FR01/18 | RED→GREEN session isolation; emulator login/restore/logout, address add/rename/delete and quota/domain/anti-bot errors, profile failure, password-change session behavior |
| T005 | Inbox/sent/starred, search and cursor paging | T004 | FR02/03/10 | Cursor fixture >50, mail arriving mid-page, stale callback tests, search UI tests |
| T006 | Native reader, OTP, safe HTML, attachment receive/send transport | T005 | FR04/05/06 | RED→GREEN ambiguous/false OTP fixtures, XSS/link/privacy tests, file bounds/cancel |
| T007 | Composer, recipients, reply/forward and encrypted autosave drafts | T004,T006 | FR07/08 | RED→GREEN address validation, draft process-kill recovery, missing file and recipient errors |
| T008 | Additive owned detail/state/labels/trash/sync schema and durable send intents | T003 | FR09/11 | Ownership cross-user tests; migration/backfill/rollback; same-key and timeout/provider-failure tests |
| T009 | Organization, thread UI, offline cache, mutations and reconciliation | T005,T007,T008 | FR09/10/11/14 | Two-device conflict fixtures; resync/tombstones; ambiguous-send explicit state |
| T010 | Rule-first OTP shared with Telegram; assistant and corrected sender rules | T006,T008 | FR05/12/13 | VI/EN corpus; source-validity; prompt-injection fixture; model timeout/cost/redaction tests |
| T011 | Push permission/device lifecycle/deep links; privacy and app settings | T004,T008,T009 | FR15/16/18 | Denied permission, logout revoke, foreign-ID deep link; controlled FCM delivery with configured credentials |
| T012 | Full acceptance, design review, security/regression evidence and signed RC | T002–T011 | FR01–18 | All journey cases mapped to evidence; Android14 physical-device check; Actions success and release notes |

## Vertical TDD rule
For T003–T011: pick one agreed public seam → write a behavioral failing test → record RED → implement minimal slice → record GREEN → review/refactor → next slice. Avoid bulk speculative tests and private-method coupling. `qa-evidence.md` records actual commands and results. Tests described here are planned, not fabricated.

## Release labels
- Foundation APK: native scaffold only.
- Daily-client APK: core email journeys, feature omissions named.
- Complete release candidate: US01–US08 gates met; still labeled candidate until device acceptance.
