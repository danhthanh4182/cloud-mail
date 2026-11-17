# Review and implementation entry point

Start with `spec.md`, then `feature-inventory.md`, `design/design-system.md` and `design/mockup.html`. The HTML is a design prototype with fictional fixtures; it never calls a mail server or sends mail. Read `plan.md`, `tasks.md`, ADRs and `qa-evidence.md` before implementing.

Spec Kit initialized through the official CLI; `.specify/memory/constitution.md` is the project constitution. The local feature pointer `.specify/feature.json` is intentionally ignored by Git. In a clean checkout/CI set `SPECIFY_FEATURE_DIRECTORY=specs/001-native-mail`; the workflow supplies it explicitly. Use the installed Codex `$speckit-*` commands for subsequent clarify/plan/tasks/analyze/implement stages.

After design approval, scaffold under `apps/mobile`, resolve stable Flutter and packages, commit SDK pin/lockfiles, and implement blockers-first. Follow `release-runbook.md`; APKs are obtained from Actions Artifacts, never committed. There is no new native APK in this design-only change.
