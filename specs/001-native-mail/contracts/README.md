# API contracts

## Existing baseline (verified from source)

All routes below are prefixed `/api`. Success: `{code:200,message:"success",data:...}`. Handle HTTP errors AND envelope errors. Raw `Authorization: <token>`; preserve `accept-language`. JSON bodies except attachment bytes. This is a discovered contract, not a promise of production configuration.

| Method + path | Input | data |
|---|---|---|
| POST /login | {email,password} | {token} |
| DELETE /logout | no body | null |
| GET /my/loginUserInfo | none | user/profile object |
| PUT /my/resetPassword | {password} | null |
| GET /account/list | accountId,size<=30,lastSort | array of accounts |
| POST /account/add | {email,token} | account; token may be anti-bot requirement |
| PUT /account/setName | {accountId,name} | null |
| DELETE /account/delete | accountId | null; confirm dependent-data impact |
| GET /email/list | accountId,allReceive,emailId,timeSort,size<=50,type=0/1,full=1,searchType,text,startDate,endDate | {list,total,latestEmail} |
| GET /email/latest | emailId,accountId,allReceive | array of newer received mail |
| PUT /email/read | {emailIds:[number]} | null; only mark-read |
| DELETE /email/delete | emailIds comma-separated | null; potentially permanent |
| POST /star/add | {emailId} | null |
| DELETE /star/cancel | emailId | null |
| GET /star/list | emailId,size,full=1 | {list}, no total |
| POST /email/send | accountId,name,sendType,emailId,receiveEmail[],ccEmail[],bccEmail[],text,content,subject,manyType,attachments[] | server send result; adapter handles partial failures |
| GET /email/attList | emailId | owned attachment metadata |
| GET /oss/* | key in path | binary; access policy requires review |

Email fields include emailId,accountId,userId,sendEmail,name,toEmail,recipient,cc,bcc,subject,text,content,code,type,status,unread,createTime,inReplyTo,relation,messageId,attList. `unread=0` is unread. `recipient/cc/bcc` can be JSON-encoded strings rather than arrays. Null fields are legal. `content` is untrusted HTML. `attachments[].content` on send is raw base64, not a data URL.

## Proposed additive mobile API (NOT IMPLEMENTED)

Every endpoint authenticates user ownership, validates IDs, bounds pages/files and returns typed errors. Define exact JSON Schema/OpenAPI and fixtures in T003 before implementation. Existing endpoints cannot be silently repurposed.

| Endpoint | Purpose | Requirements |
|---|---|---|
| GET /mobile/capabilities | version/feature support and policy | explicit folder,AI,push,limits,delete-policy fields |
| GET /mobile/mail/:id | owned detail and safe attachment descriptors | 404 for foreign IDs; safe R2 transport |
| POST /mobile/mutations | versioned read/star/folder/label operations | per-item result and conflict; no raw arbitrary writes |
| GET /mobile/sync?cursor= | changed mail/state/tombstones | monotonic per-user cursor, bounded page, full-resync signal |
| POST /mobile/send | durable idempotent send intent | Idempotency-Key, payload hash and stable result |
| GET /mobile/send/:key | reconcile uncertain send | owner-bound; no implicit retry |
| GET/PUT /mobile/drafts/:id | opt-in cross-device draft | revision conflict, attachment references |
| GET/POST /mobile/labels | manage labels | owner namespace |
| POST /mobile/assistant/:id | summary/category/reply suggestion | opt-in, bounded input, source membership, no actions |
| POST /mobile/search/parse | natural language -> allowed filters | response preview, no arbitrary SQL |
| POST/DELETE /mobile/push/devices/:id | push registration/revocation | token ownership and consent |

Compatibility: clients work with baseline functions on older deployments, clearly disabling unsupported capabilities. Features in the complete release require the upgraded Worker; show supported version and upgrade link. Never forward credentials to redirects or non-configured origins. 401 expires session, 403 reports permissions, 429 honors retry hints for safe operations only.
