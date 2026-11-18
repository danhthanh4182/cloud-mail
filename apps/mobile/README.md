# Cloud Mail Native

Flutter 3.50.0 / Dart 3.14.0, Android 8+ (API26). Native Material widgets, direct HTTPS API calls; no WebView. Install the **Native Android APK** Actions artifact, not the older wrapper artifact. Application ID `dev.danhthanh.cloudmail.nativeapp` deliberately installs alongside the old wrapper.

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

GitHub Actions runs Worker and Flutter tests, builds a **debug test-signed APK**, verifies its signature and attaches source SHA + SHA256 checksums. APKs, signing keys, Gradle output and private data must never enter Git. Release signing is intentionally unconfigured. Debug signatures may change between clean hosted runners; uninstalling to switch keys also deletes device drafts, so export/retain important content first.

## Current acceptance boundary

This is a daily-client implementation milestone, not the complete Gmail-like release. Remaining gates: Android physical-device acceptance, rich HTML table fidelity, full threading, cross-device draft UI, offline mutation queue, push/FCM lifecycle, natural-language search and corrected sender rules. Push is explicitly unavailable; foreground refresh is not push. No real mail has been sent by development tests.
