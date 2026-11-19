-- Additive migration. Apply to staging before enabling mobile features.
CREATE TABLE IF NOT EXISTS mobile_mail_state (
 user_id INTEGER NOT NULL, email_id INTEGER NOT NULL,
 folder TEXT NOT NULL DEFAULT 'inbox' CHECK(folder IN ('inbox','archive','spam','trash')),
 labels TEXT NOT NULL DEFAULT '[]', version INTEGER NOT NULL DEFAULT 0,
 updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(user_id,email_id)
);
CREATE TABLE IF NOT EXISTS mobile_event (
 sequence INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL,
 email_id INTEGER NOT NULL, version INTEGER NOT NULL, created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS mobile_event_owner_cursor ON mobile_event(user_id,sequence);
CREATE TABLE IF NOT EXISTS mobile_send_intent (
 user_id INTEGER NOT NULL, request_key TEXT NOT NULL, account_id INTEGER NOT NULL,
 payload_hash TEXT NOT NULL, state TEXT NOT NULL DEFAULT 'pending', result TEXT,
 created_at TEXT DEFAULT CURRENT_TIMESTAMP, updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(user_id,request_key)
);
CREATE TABLE IF NOT EXISTS mobile_draft (
 user_id INTEGER NOT NULL, draft_id TEXT NOT NULL, account_id INTEGER NOT NULL,
 revision INTEGER NOT NULL DEFAULT 1, payload TEXT NOT NULL,
 updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(user_id,draft_id)
);
CREATE TABLE IF NOT EXISTS mobile_label (
 user_id INTEGER NOT NULL, label_id TEXT NOT NULL, name TEXT NOT NULL,
 color TEXT NOT NULL DEFAULT '#2458D3', PRIMARY KEY(user_id,label_id)
);
CREATE TABLE IF NOT EXISTS mobile_device (
 user_id INTEGER NOT NULL, device_id TEXT NOT NULL, token TEXT NOT NULL,
 updated_at TEXT DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(user_id,device_id)
);
