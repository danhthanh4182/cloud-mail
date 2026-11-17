# Fork + mobile development + upstream sync

## Ownership boundary
| Paths | Owner / purpose | Sync policy |
|---|---|---|
| mail-vue/** | upstream webmail + reviewed local patches | preserve upstream layout, avoid unrelated refactors |
| mail-worker/src/** (existing modules) | upstream backend + integration hooks | keep minimal hooks and regression tests |
| apps/mobile/** | fork-owned Flutter client | upstream merge must preserve it |
| mail-worker/src/{api,service}/mobile* and migrations | additive fork mobile APIs | version/capability contract; migrations reviewed |
| specs/**, .harness/**, docs/adr/** | fork product process | preserve; review if upstream introduces same paths |
| .github/workflows/mobile-*.yml | fork mobile verification/build | keep distinct names and source-only policy |

## Branch policy
`main` is the integrated fork; `001-native-mail` is current specification branch. Native implementation uses short feature branches with requirement IDs. `sync/upstream-<date>` is only for importing upstream. Do not develop directly on a long-lived sync branch. Independent source commits make conflict intent easier to understand; they are not a guarantee of conflict-free merges.

## Safe routine
1. Add remote once: `git remote add upstream https://github.com/maillab/cloud-mail.git`.
2. `git fetch origin` and `git fetch upstream`; inspect upstream commits and compare merge base.
3. Start clean from fork main: `git switch -c sync/upstream-YYYY-MM-DD origin/main`.
4. Merge upstream's verified default branch without squash. Review every conflict against both changes; never blanket choose ours/theirs.
5. Run source guardrails, existing Worker/web checks and native tests. Review migrations, authentication, send/attachments contracts, version changes and workflow permissions.
6. Open a PR to fork main with upstream range, conflict resolutions and evidence. Merge only after authorization and passing checks. Build new APK via Actions after integration; never commit artifacts.
7. Update contract fixture baseline and release notes when backend behavior changes. Capability-gate old servers; do not require every app user to upgrade the same moment.

## What does not work safely
- Resetting fork main to upstream discards fork-owned commit history/changes.
- Periodic automatic merge/deploy bypasses compatibility and migration review.
- Assuming isolated directories eliminate dependency, entrypoint and database conflicts.
- Editing generated APKs instead of changing source and rebuilding.

## Current implementation status
This is the proposed maintenance process, not a claim that an upstream sync has run. No upstream merge, production deployment or repository default-branch update is performed as part of preparing this design.
