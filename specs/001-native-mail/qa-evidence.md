# QA strategy and evidence

Status: native daily-client implementation milestone, PR #9. Flutter analyze and 27 automated Flutter tests pass; Worker 91 unit and 3 runtime tests pass. The native APK is built through Actions. Device/live-send/push/production compatibility acceptance remains pending. The old wrapper build is superseded and is not native-product evidence.

## Planned matrix
| Area | Cases | Environment / gate |
|---|---|---|
| Domain | OTP VI/EN, ambiguous codes, amounts/order IDs, address parsing, send transitions | deterministic unit fixtures |
| API | exact envelope shapes/raw token, 200 errors, HTML body, timeout, 401/403/429 | repository contract tests |
| Backend | cross-user access, same idempotency key/different hash, unknown provider result, sync version | Worker integration tests with isolated D1/R2 |
| UI | inbox/search/reader/OTP/compose/drafts/settings; loading/empty/error/offline | Flutter widget + goldens light/dark |
| Accessibility | TalkBack labels/order, 48dp, contrast, 200% scaling, keyboard focus | automated checks + manual Android |
| Devices | Android8/API26 where plugin support permits; Android14/API34; modern target; 360/412/tablet | emulator + representative physical device |
| End-to-end | login→list→read→copy→draft→send→receive, attachment and deletion policy | controlled accounts only; no external messages without user authorization |
| Privacy | no secrets in logs/cache backups; images opt-in; safe links/HTML/AI | static review + adversarial fixtures |
| Delivery | Flutter analyze/tests, Worker regressions, build/sign/manifest verify | GitHub Actions; APK/AAB only artifacts |

## Evidence log
| Date | Check | Result |
|---|---|---|
| 2026-11-18 | Source/API inventory | Read baseline files; listed research.md |
| 2026-11-18 | Official Spec Kit init | CLI scaffold completed; upstream revision in research.md |
| 2026-11-18 UTC | Native analysis/unit/widget | Passed locally and in Actions; 360/412/840px × 100/200% text; hardware acceptance pending |
| 2026-11-18 UTC | Worker additive migration/ownership/send/assistant tests | 91 unit + 3 Cloudflare runtime passed; production migration not run |
| Pending | Live deployment acceptance/push | Requires configured controlled deployment and credentials |

Coverage numbers and performance measurements are published only from actual runs. A mockup screenshot is design evidence, never evidence of APK behavior.

## Design/harness verification (actual, 2026-11-18)

- `python3 -m unittest discover -s tests/harness -v`: 5 tests passed. Negative cases reject tracked APK/keys, DAG cycles, stale evidence and missing decision/check references.
- `python3 scripts/harness.py verify`: passed source/design structure and guardrail checks (not runtime application tests).
- Official `check-prerequisites.sh --json --require-tasks --include-tasks`: resolved this feature and required task documents.
- `python3 scripts/harness.py release-check`: failed in design phase as intended. Design is now approved; complete device/integration/signing evidence remains pending. This failure is expected, not waived.
- Headless prototype interaction check: rendered light/dark/wireframe/component boards; tested search, empty results, reader navigation and simulated-send confirmation with no page errors. Local Chromium launcher was unsupported; verification used a standalone Chrome Headless Shell. This is web prototype evidence only.
- Independent Spec and Standards reviewers reported six documentation/harness/UI findings. Corrected FR18 behavioral cases, provider-aware send guarantees, artifact-policy wording, all-PR guardrail trigger, rendered mobile typography/targets and modal focus handling. Device/TalkBack checks remain pending.

- `npm run test:design --prefix .harness`: reusable prototype regression includes visible mobile button targets >=48px, search/empty/reader/theme behavior and modal forward/reverse tab trap plus focus restoration. Local run sets MOCKUP_BROWSER to the standalone headless shell; CI uses Playwright installed Chromium. This is not native-device certification.
