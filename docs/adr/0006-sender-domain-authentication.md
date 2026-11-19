---
status: accepted
---
# Record sender-domain authentication at the receiving gateway

Cloudflare Email Routing evaluates DMARC before invoking the Email Worker. Its [Workers API documentation](https://developers.cloudflare.com/email-service/api/route-emails/email-handler/#authentication-results) identifies the first Authentication-Results field from `mx.cloudflare.net` as the trusted result. Evaluate that field at direct ingress. Record positive evidence only, keyed to the stored message. Avoid retaining raw headers for badge display or deriving a badge from mail content, sender names, addresses alone or later result fields. When the runtime or MIME parser exposes combined or repeated result fields, treat the result as ambiguous. Some forwarded mail may therefore lack a badge even after passing the gateway check.

Expose the evidence through the authenticated, ownership-scoped mobile API. A missing result leaves the badge hidden, including for messages received before recording was enabled. The badge describes authentication of the From domain by DMARC. The interface explains that scope independently of authenticity of individual people, brands or message content.

Use initials based on the address and display name when rendering message participants. Remote avatar lookups would disclose participants' addresses to another provider and require a separate data source and consent design.
