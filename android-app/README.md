# Cloud Mail Android — 0.1.0

Android WebView client for the existing Vue 3 / Cloudflare Cloud Mail deployment.
Based on danhthanh4182/cloud-mail, commit 2763a30. Android 8+ (API 26), target API 35.

## Install and use

Install cloud-mail-0.1.0-debug.apk, allow installation from the app opening the file,
and enter your own deployed Cloud Mail HTTPS URL on first launch. No demo server or
credentials are preconfigured. Log in with your existing webmail account.
The app requires a working Cloud Mail deployment; it does not host the Worker locally.

Supports persistent WebView login, native file picker for attachments, refresh,
back navigation, server switching and clearing local login. Other origins and
user-triggered popups open in the browser. HTTPS only within the app, no JS/native
bridge, no broad storage permissions, backup disabled. Long press text to use
Android selection/copy. Existing webmail features are served by the deployment.

## Limits

This is an installable wrapper using the existing web UI, not a rewritten native
mail client. Gmail-like AI features discussed in chat have not been implemented.
No background push or offline inbox synchronization. OAuth flows requiring an
external browser may not transfer a session back to the app: use webmail password
login or the browser. Downloads open in the browser and can need a separate login;
blob downloads must be downloaded through webmail in the browser. Notification,
OAuth, attachment, clipboard and device UI behavior need testing on a real device.
Build/signature/package checks do not substitute for runtime testing.

## Rebuild

Requires Java 21 runtime, Android SDK platform 35 and Build Tools 35.0.0, zip,
and a JDK (javac) or Eclipse ECJ 3.40.0 compiler jar.

```sh
ANDROID_JAR=/path/to/android-35/android.jar \
BUILD_TOOLS=/path/to/build-tools/35.0.0 \
ECJ_JAR=/optional/path/to/ecj.jar ./build.sh
```

Output: build/cloud-mail-0.1.0-debug.apk. A test signing key is generated under
build/keys. Keep that key to rebuild compatible test updates. Use your own secure
release signing key before distribution; do not publish debug signing keys.

No upstream changes are pushed by this build. MIT license of parent project applies.

## GitHub Actions distribution

Workflow: `.github/workflows/android-apk.yml` (Build Android APK).
Runs for Android changes on main, codex/android-apk, relevant pull requests,
and manual dispatch. Download the APK from the run's Actions Artifacts section.
APK/AAB/build output and signing keys are ignored and must never be committed.
Each CI build generates an ephemeral test key; to update an earlier CI-installed
APK you may need to uninstall it first. Stable production updates require a
persistent release signing key stored in GitHub Actions secrets, never in Git.
