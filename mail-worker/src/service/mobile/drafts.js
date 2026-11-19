import BizError from '../../error/biz-error';

function validateId(id) {
 if (!/^[\w-]{1,100}$/.test(id)) throw new BizError('Invalid draft ID',400);
}

function replicaPayload(id,payload) {
 const clean = {
  id,accountId:payload.accountId,
  attachmentCount:Number.isInteger(payload.attachmentCount)?Math.min(10,Math.max(0,payload.attachmentCount)):
   Array.isArray(payload.attachments)?Math.min(10,payload.attachments.length):0,
  replyId:Number.isSafeInteger(payload.replyId)?payload.replyId:0,
  sendType:['reply','forward'].includes(payload.sendType)?payload.sendType:'',
 };
 for (const name of ['to','cc','bcc','subject','body']) {
  clean[name]=typeof payload[name]==='string'?payload[name]:'';
 }
 return clean;
}

// Keep worst-case UTF-8 page size below the Android API response budget.
const pageSize=20;

export async function getDrafts(db,userId,cursor='') {
 if (cursor) validateId(cursor);
 const {results} = await db.prepare(`
  SELECT draft_id, account_id, revision, payload, 0 AS deleted FROM mobile_draft WHERE user_id=? AND draft_id>?
  UNION ALL
  SELECT draft_id, 0, revision, NULL, 1 FROM mobile_draft_tombstone WHERE user_id=? AND draft_id>?
  ORDER BY draft_id LIMIT ?
 `).bind(userId,cursor,userId,cursor,pageSize+1).all();
 const list=results.slice(0,pageSize).map(row=>({
  draftId:row.draft_id,revision:row.revision,deleted:row.deleted===1,
  payload:row.payload ? replicaPayload(row.draft_id,JSON.parse(row.payload)) : null,
 }));
 return {list,nextCursor:results.length>pageSize ? list.at(-1).draftId : null};
}

export async function putDraft(db,userId,id,body) {
 validateId(id);
 const {revision,payload}=body ?? {};
 if (!Number.isSafeInteger(revision) || revision<0 || !payload || payload.id!==id ||
     !Number.isSafeInteger(payload.accountId)) throw new BizError('Invalid draft',400);
 const clean=replicaPayload(id,payload);
 const json=JSON.stringify(clean);
 if (new TextEncoder().encode(json).length>400000) throw new BizError('Draft text exceeds sync limit',413);
 const account=await db.prepare('SELECT 1 FROM account WHERE account_id=? AND user_id=? AND is_del=0')
  .bind(clean.accountId,userId).first();
 if (!account) throw new BizError('Sender not found',404);
 const statement=revision===0 ? db.prepare(`
  INSERT OR IGNORE INTO mobile_draft (user_id,draft_id,account_id,revision,payload)
  SELECT ?,?,?,1,? WHERE NOT EXISTS (SELECT 1 FROM mobile_draft_tombstone WHERE user_id=? AND draft_id=?)
 `).bind(userId,id,clean.accountId,json,userId,id) : db.prepare(`
  UPDATE mobile_draft SET payload=?,account_id=?,revision=revision+1,updated_at=CURRENT_TIMESTAMP
  WHERE user_id=? AND draft_id=? AND revision=?
 `).bind(json,clean.accountId,userId,id,revision);
 const written=await statement.run();
 if (!written.meta.changes) throw new BizError('Draft changed on another device',409);
 return {draftId:id,revision:revision+1};
}

export async function deleteDraft(db,userId,id,revision) {
 validateId(id);
 if (!Number.isSafeInteger(revision) || revision<=0) throw new BizError('Draft revision required',400);
 const [deleted]=await db.batch([
  db.prepare('DELETE FROM mobile_draft WHERE user_id=? AND draft_id=? AND revision=?').bind(userId,id,revision),
  db.prepare(`INSERT INTO mobile_draft_tombstone(user_id,draft_id,revision)
   SELECT ?,?,? WHERE changes()>0 ON CONFLICT(user_id,draft_id) DO NOTHING`).bind(userId,id,revision+1),
 ]);
 if (!deleted.meta.changes) {
  const tombstone=await db.prepare('SELECT revision FROM mobile_draft_tombstone WHERE user_id=? AND draft_id=?')
   .bind(userId,id).first();
  if (!tombstone || tombstone.revision!==revision+1) throw new BizError('Draft changed on another device',409);
 }
}
