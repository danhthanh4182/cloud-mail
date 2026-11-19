---
status: accepted
---
# Rule-first OTP and bounded AI assistance

Use deterministic source-validated OTP extraction first; optional Workers AI handles ambiguous cases and summaries through structured output. Sending all mail to a general model would be easy but increases exposure, latency and false confidence. Redact OTPs, credentials and login URLs before general summaries, cap inputs/jobs/cost and cache by content hash + model version.

AI outputs are untrusted metadata and suggestions. Email text cannot authorize actions or override system instructions. The user controls send/delete; assistant failure cannot block mail ingestion or reading. Corrected labels become explicit per-user rules, not an unexplained claim of online model training.
