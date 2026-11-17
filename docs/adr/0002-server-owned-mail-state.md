---
status: proposed
---
# Server-owned organization with an isolated encrypted offline cache

Keep labels, archive/spam/trash/read state authoritative on the Worker/D1 and expose additive, owner-checked mobile endpoints. A local-only label system would be simpler but would disagree with other devices and cannot honestly support the requested complete mail experience. Existing web/Telegram contracts remain compatible; mobile negotiates capabilities before enabling new features.

Cache/drafts are isolated by server and user and encrypted at rest; credentials use Android-backed secure storage. Database migrations and tombstones require rollback/retention handling before production rollout. Sensitive cached data is excluded from Android backups.
