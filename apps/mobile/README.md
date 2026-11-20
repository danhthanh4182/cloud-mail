# Cloud Mail Native

Flutter 3.50.0 / Dart 3.14.0, Android 8+ (API26). Native Material widgets and direct HTTPS API calls. The **Native Android APK** workflow builds Cloud Mail Preview with application ID `dev.danhthanh.cloudmail.nativeapp.preview`. It installs alongside Cloud Mail and keeps its own sign-in and local drafts. Signed release candidates use `dev.danhthanh.cloudmail.nativeapp`.

## Run and verify

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run
```

Use the webmail HTTPS origin on the sign-in screen. Raw legacy JWT transport and `code=200` envelopes are handled by one API adapter. Passwords are never persisted. Device keystore-backed storage contains identity-scoped sessions, drafts and bounded caches; Android backup is disabled.

The new Worker endpoints require `mail-worker/migrations/001_mobile.sql`, applied only to a controlled test deployment first. No migration/deploy runs in this APK workflow. Legacy servers support inbox/read/star/search, but organization and safe send are capability-gated. Do not bypass the send gate with the old non-idempotent endpoint.

## Distribution

GitHub Actions runs Worker and Flutter tests, builds a **debug test-signed Preview APK**, verifies the signature, package ID and launcher name, and attaches the source revision and SHA256 checksum. Open `cloud-mail-preview.apk` from the Actions artifact and keep the installed Cloud Mail app to preserve its local drafts. Preview uses separate storage, so sign in again. APKs, signing keys, Gradle output and private data must never enter Git.

The Preview key can change between hosted runners. A signed release built with the same configured release certificate supports in-place updates. For a Preview-to-Preview signer conflict, retain any needed Preview drafts before switching builds.

## Android completion features and configuration

Android 0.3 adds header-based conversations, native HTML formatting and tables, per-message HTTPS image consent, controlled attachment download and forwarding, versioned draft replicas, offline edits, sender categorization, editable natural-language filters, AI reply suggestions and Firebase push.

Apply `mail-worker/migrations/001_mobile.sql` and then `002_mobile_completion.sql` to **staging** before enabling v2 features. The app negotiates capabilities. Draft text and the attachment count are replicated; file bytes and unresolved send intents stay with the originating device. Pending reversible edits are persisted locally and checked against server versions on reconnect.

The Android reader keeps message tables, embedded CSS and inline links in an isolated HTML body. HTTPS images require consent for each message, and links open only after confirmation. The reader also displays sender and recipient initials and surfaces assigned labels in both the mailbox and reader. Apply `003_sender_authentication.sql` after the first two migrations and deploy the matching Worker to staging to record DMARC evidence for newly received messages through Cloudflare Email Routing. Existing messages remain readable without a badge.

For push, register the Android app matching the build being tested. Signed releases use the `CLOUD_MAIL_FCM_APP_ID`, `CLOUD_MAIL_FCM_API_KEY`, `CLOUD_MAIL_FCM_PROJECT_ID`, and `CLOUD_MAIL_FCM_SENDER_ID` Actions variables for `dev.danhthanh.cloudmail.nativeapp`. Preview uses the corresponding `CLOUD_MAIL_PREVIEW_FCM_*` variables for `dev.danhthanh.cloudmail.nativeapp.preview`. Configure the Worker secret `MOBILE_FCM_SERVICE_ACCOUNT` with the matching service account JSON and FCM HTTP v1 permissions. An Android 13+ device must allow notification permission. A Firebase-enabled device or emulator with Google Play services is required.

The manual **Signed Android release candidate** workflow uses the `android-release` environment and its `CLOUD_MAIL_KEYSTORE_BASE64`, `CLOUD_MAIL_SIGNING_STORE_PASSWORD`, `CLOUD_MAIL_SIGNING_KEY_ALIAS`, and `CLOUD_MAIL_SIGNING_KEY_PASSWORD` secrets. Set `CLOUD_MAIL_SIGNING_CERT_SHA256` to the expected certificate fingerprint. The workflow verifies that fingerprint before attaching the APK.

See [completion acceptance](../../specs/001-native-mail/completion-acceptance.md) and [QA evidence](../../specs/001-native-mail/qa-evidence.md) for measured results and live acceptance status.
