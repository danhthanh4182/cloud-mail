---
status: proposed
---
# Keep mobile extensions in the fork with explicit upstream merge boundaries

Keep `apps/mobile` and mobile-specific Worker modules/specs/tests/workflows in this fork. Preserve upstream web/Worker layout and make small explicit integration imports rather than refactoring unrelated upstream files. A separate mobile repository reduces tree overlap but requires coordinated releases across repos; a monorepo provides a single tested app/backend contract and simpler initial maintenance.

Sync `maillab/cloud-mail` into a temporary `sync/upstream-*` branch targeting fork `main`, review conflict intent and run web/Worker/mobile checks, then authorize the merge. Never hard-reset the fork to upstream, force-push it or automatically accept upstream on conflict. UI isolation lowers conflicts; shared entrypoints/dependencies/schema can still conflict and require review. Revalidate upstream features before retaining a custom patch that upstream now provides.
