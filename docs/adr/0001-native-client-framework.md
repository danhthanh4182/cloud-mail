---
status: proposed
---
# Flutter client alongside the existing Vue webmail

Use a dedicated Flutter application under `apps/mobile` with official Material 3 widgets, communicating directly with the existing Worker. Flutter supplies a coherent mobile design system and leaves a path to iOS; Kotlin Compose remains the strongest alternative if Android becomes the sole long-term target. Vue remains the web client. A WebView shell is rejected because the user explicitly rejected that experience, even though it was faster to package.

Consequence: the new client must implement and test the email journeys; packaging the website is no longer considered a mobile deliverable. Runtime package versions must be resolved/pinned during implementation and lockfiles committed.
