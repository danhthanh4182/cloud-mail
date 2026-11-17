---
status: accepted
---
# Build APKs exclusively through GitHub Actions for distribution

The user explicitly requires workflows and forbids committing build files. Commit source, design source, specifications, migrations, lockfiles and workflows only. Actions runs verification then builds APK/AAB; publish binaries to Actions Artifacts or approved release assets, never to the repository tree.

Production signing keys are persistent CI secrets, not regenerated every build. Test keys must not be presented as release signing. A CI guard rejects tracked build artifacts and signing material. Merging a PR or deploying backend migrations remains a separate authorized action.
