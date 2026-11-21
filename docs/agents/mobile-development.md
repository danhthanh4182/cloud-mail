# Mobile engineering playbook

Skill coverage: Flutter Mobile Engineering (typed repositories/state/tests), Android Platform Engineering (lifecycle, permissions, storage, push/signing), Mobile Design Quality (tokens, mockups, adaptive accessibility). These are custom skills prepared for this workflow, not official Flutter/Google packages. Canonical project constraints remain here and in AGENTS.md so another developer can work without a personal skill installation.

Use official Flutter architecture/testing/deployment documentation and Android architecture/background/permission/signing documentation. Resolve versions against the actual app's SDK and lockfile. In particular periodic background work is deferrable and cannot be sold as instant push. Avoid platform-permission shortcuts or broad storage access.

Separate UI/state/domain/repository boundaries. Derive contracts from backend source and fixtures. Identity-scope cache, use platform-backed secure storage, encrypt private offline data. Retain drafts on process death and handle missing attachment URIs. Treat provider responses and AI text as untrusted, preserve ambiguous-send states.

Use official Material3 components in the real Flutter app. Semantic light/dark tokens, 48dp targets, VI/EN strings, readable 200% scale and TalkBack order are acceptance requirements. Mockups only illustrate intended behavior; they cannot establish implementation/device performance.

A source-only PR includes tests and evidence. Production readiness needs actual unit/widget/backend/integration/device/signing results and required configuration, not a successful APK build alone.
