# SDLC and release runbook

1. **Discovery**: source inventory and capability matrix; keep unknown production facts explicit.
2. **Definition/design**: approve spec, test seams, architecture, design system and key mockups. ADR proposed→accepted only after decision.
3. **Planning**: tasks with blocking dependencies and acceptance tests; trace US→FR→task→evidence.
4. **Implementation**: one vertical slice at a time, tests first at agreed seams, type checks and focused regressions.
5. **Review**: independent Standards and Spec reviews; resolve blocking findings, record deferrals as tasks.
6. **Verification**: unit/contract/widget/integration/security/migration/visual/a11y checks plus existing web/Telegram regressions.
7. **Delivery**: Actions builds APK; verify signer/package/minSdk and attach checksums. Source tree guard rejects *.apk/*.aab/*.keystore/*.jks/build outputs. Release signing keys only CI secrets; no binary commits.
8. **Rollout**: staging Worker migration + feature flag, controlled device acceptance, then authorized production rollout. Users on old Worker get capability-gated UI.
9. **Operation**: redact logs; monitor ingestion/send failures/sync lag/assistant budget/push failures without storing bodies or OTPs.
10. **Rollback**: disable new features first, stop new writers, roll back app via known-good signed build if needed. D1 additive migrations avoid destructive rollback; retained old code paths remain compatible. Send idempotency records must survive rollback.

**Production-readiness blockers**: exact deployment URL/version, push infrastructure provisioning, stable release signer, migrated-state staging test, physical Android device acceptance. None are required to draw the design; each is required for the corresponding release claim.
