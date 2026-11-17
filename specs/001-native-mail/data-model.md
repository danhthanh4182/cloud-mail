# Domain and storage model (proposed additions)

Existing entities remain `user`, `account`, `email`, `attachments`, `star`. A User owns Addresses (API: accountId); each Mail belongs to one User and Address. Read state must preserve the existing unread 0/1 convention through an adapter.

| Proposed entity | Key | Required data/invariants |
|---|---|---|
| MobileSession | serverOrigin + userId | Token in platform secure storage; no password; cache encryption key scoped to identity |
| CachedMail | origin,userId,emailId | Metadata/body version,lastSynced; encrypted private data; bounded retention |
| Draft | origin,userId,draftId | senderId,To/CC/BCC,subject,body,localAttachmentRefs,updatedAt,revision |
| MailState (D1) | userId,emailId | folder,labels,read flag,version,updatedAt; ownership checked on every write |
| Label (D1) | userId,labelId | name,color,rule references; no global cross-user labels |
| SyncEvent (D1) | userId,sequence | entityId,version,operation,tombstone; retained cursor window |
| PendingMutation | identity,mutationId | reversible action,baseVersion,retryCount; never generic queued send |
| SendAttempt (D1) | userId,idempotencyKey | canonical request hash,status,providerId,result,expiry; same key + different hash rejected |
| AssistantResult (D1) | userId,emailId,contentHash,modelVersion | category,summary,sourceEvidence,priority,redactionVersion |
| PushDevice (D1) | userId,deviceId | token hash/encrypted transport token,platform,consent,lastSeen; revoke at logout |

SendAttempt states: pending → provider_submitted → accepted / rejected / unknown. Provider timeout becomes unknown; reconciliation must precede retry. Provider without idempotency support cannot guarantee exactly-once after a crash; document and surface this boundary rather than claiming exactly-once delivery.

Local mutation states: queued → inFlight → acknowledged / conflict / blockedAuth. Optimistic read/star/archive updates retain their previous value for rollback. Sync cursor older than retention requests an authenticated full resync without deleting unsent drafts.

Delete policy: trash and retention are new stateful operations; existing /email/delete may physically delete. Do not call it to implement reversible trash. Cross-user foreign keys and indexes belong in migration contract tests; migrations are additive, backfill in bounded batches, and feature flag gates new writers.
