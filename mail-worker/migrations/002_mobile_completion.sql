-- Apply after 001_mobile.sql. These changes do not rewrite existing mail.
CREATE INDEX IF NOT EXISTS mobile_email_message_id ON email(user_id,account_id,message_id);
CREATE INDEX IF NOT EXISTS mobile_email_reply_id ON email(user_id,account_id,in_reply_to);

CREATE TABLE IF NOT EXISTS mobile_draft_tombstone (
 user_id INTEGER NOT NULL, draft_id TEXT NOT NULL, revision INTEGER NOT NULL,
 PRIMARY KEY(user_id,draft_id)
);
CREATE TABLE IF NOT EXISTS mobile_sender_rule (
 user_id INTEGER NOT NULL, sender TEXT NOT NULL, category TEXT NOT NULL,
 PRIMARY KEY(user_id,sender)
);
CREATE TABLE IF NOT EXISTS mobile_ai_hour (
 user_id INTEGER PRIMARY KEY, hour INTEGER NOT NULL, count INTEGER NOT NULL
);
-- A registration is tied to a session and installation, and expires without renewal.
CREATE TABLE IF NOT EXISTS mobile_push_registration (
 device_id TEXT PRIMARY KEY, user_id INTEGER NOT NULL, token TEXT NOT NULL UNIQUE,
 session_hash TEXT NOT NULL, rotation_hash TEXT, expires INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS mobile_push_owner ON mobile_push_registration(user_id,expires);
