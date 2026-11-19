# Functional inventory

| Capability | Current source | Native app work | Backend work |
|---|---|---|---|
| Password login/logout/profile | Existing | Native forms, secure token and errors | Capability response, optional OAuth bridge |
| Multiple email addresses | Existing list/add/name/delete | Picker, management and validation | Preserve quotas and domain rules |
| Inbox/sent/starred/search | Existing | Typed client, cursor state, native UI | Owned detail endpoint for efficient reader |
| Read status/star | Existing read-only transition/add/cancel | Mutations and reconciliation | Mark-unread endpoint |
| Read HTML/text | Existing fields | Sanitized native layout-table flow, scrollable data tables and consent for remote resources | Attachment/detail authorization audit |
| Message identity and labels | Sender, recipient and CC fields; mobile labels | Local initials, address details, label previews and DMARC domain badge for new mail with evidence | Direct gateway evidence captured by the Worker after migration 003; legacy mail still opens |
| OTP | Existing AI extraction + Telegram copy | Rule extractor + copy component | Improved source-validated fallback shared with Telegram |
| Send/reply/forward | Existing send endpoint | Composer, recipients, explicit send result | Durable send idempotency/status |
| Attachments | Base64 send + R2 download | Picker, bounds, progress, local copies | Authenticated download metadata and limits |
| Drafts | Browser-local IndexedDB | Encrypted device drafts | Cross-device draft synchronization if enabled |
| Archive/spam/labels/trash restore | No user contract found | Full folder actions and state | Add owned state/labels/tombstones and capability gating |
| Threading | inReplyTo/relation/messageId fields | Thread reader | Safe References/In-Reply-To grouping; never subject-only |
| AI summaries/classification/replies | No general mail assistant service found | Explainability, corrections, settings | Structured AI jobs, limits, redaction, caching |
| Natural-language search | Existing structured search only | Show converted filters | Bounded structured filter translation |
| Offline and background sync | No native infrastructure | Encrypted cache, mutation queue and resume | Versioned sync endpoint and tombstones |
| Push | Telegram forwarding exists | Android permission/channel/deep links | FCM token ownership, enqueue delivery/revocation |
| VI/EN and themes | Web app has i18n | Mobile ARB translations and theme tokens | Preserve accept-language behavior |
| System administration | Existing web console | Link to administration, clearly external | No mobile admin parity promised without new scope |
