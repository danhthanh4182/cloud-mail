# Cloud Mail Engineering Constitution

Version: 1.0.0 · Ratified: 2026-11-18 · Status: proposed, except explicit user constraints below.

1. **Native application**: Android screens use native-rendered widgets and direct API calls. Hosting the existing website in a WebView does not satisfy the product requirement.
2. **Specification before implementation**: Every user journey has acceptance criteria, a task owner, dependencies and test evidence. Proposed decisions and untested behavior are labeled honestly.
3. **Existing behavior first**: Backend contracts are discovered from source; proposed endpoints are separated from implemented endpoints. Backend changes are additive and preserve webmail/Telegram compatibility.
4. **Secrets and mail privacy**: No plaintext password persistence. Encrypt sessions and private offline data, segregate by server/user. Do not log tokens, OTPs or full mail bodies. AI receives the minimum content with sensitive fields redacted by default.
5. **Data integrity**: Offline reversible edits may queue. Sending requires explicit user action and durable idempotency; never blindly retry ambiguous sends. AI does not autonomously send, delete or unsubscribe.
6. **Design system**: Semantic tokens and shared components govern light/dark themes, typography, spacing, interaction states and accessibility. Touch targets >=48 logical px, body text >=16sp, text scaling up to 200% must remain usable.
7. **Test evidence**: Use TDD at agreed domain/API/sync seams. Require analysis, unit, widget, contract, migration and critical-device-journey checks before production readiness. A successful compile alone is not acceptance.
8. **Build distribution**: User-mandated: never commit APK/AAB/build output or signing keys. GitHub Actions builds; artifacts or release attachments distribute binaries. Production keys belong in CI secrets. No merge or production deployment without authorization.
9. **Release honesty**: Unconfigured push, missing credentials, untested device cases and server-version limitations remain visible in release notes. No fabricated completion.

Amendments require a documented rationale and updated affected ADR/spec/test mappings.
