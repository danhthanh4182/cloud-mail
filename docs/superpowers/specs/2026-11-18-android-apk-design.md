# Android APK for current Cloud Mail

User requested an installable Android APK, delegating framework choice. Existing
Vue 3 UI and same-origin /api routing favor a native WebView host over rewriting
all views in Flutter. A Capacitor bundle would need API/CORS and deployment URL
configuration; Flutter would duplicate the current frontend.

Use platform Java + WebView, Android 8+, targeting Android 15. Configure the user's
own HTTPS deployment on first launch because its URL is not in the repository.
Preserve web login, allow file selection with system picker, open external links
in browser, expose refresh/server selection/clear-session. No native JavaScript
bridge or embedded secrets. Existing backend remains authoritative.

Deliver a test-signed APK and reproducible source. Verify DEX packaging, declared
permissions, SDK levels and signing. State explicitly that device testing, push,
offline sync and Gmail-like AI functionality are outside this initial wrapper.
