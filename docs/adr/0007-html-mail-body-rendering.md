---
status: accepted
---
# Render Android message bodies with the system HTML engine

The original Flutter body renderer flattened presentation tables and discarded author CSS. Marketing grids and verification buttons need the browser's HTML and CSS layout. Use Android WebView for the contents of a single message body. Flutter owns the reader chrome, headers, OTP, attachments, controls and interaction with the mail API.

The body renderer receives a sanitized document over a local channel. JavaScript, WebView network requests, file and content access are disabled. HTTPS images travel through the app's unauthenticated, bounded image loader after consent for the current message. Link taps go back to Flutter for confirmation. The existing Flutter body renderer provides a reading fallback if the system renderer is unavailable.
