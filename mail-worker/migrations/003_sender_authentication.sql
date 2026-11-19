-- Only direct Email Worker ingress may write this provider-derived evidence.
-- Legacy/imported mail has no evidence and must not gain an authenticated badge.
CREATE TABLE IF NOT EXISTS mobile_sender_authentication (
 email_id INTEGER PRIMARY KEY REFERENCES email(email_id) ON DELETE CASCADE,
 user_id INTEGER NOT NULL,
 sender_domain_authenticated INTEGER NOT NULL CHECK(sender_domain_authenticated=1)
);
