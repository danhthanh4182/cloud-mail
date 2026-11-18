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
