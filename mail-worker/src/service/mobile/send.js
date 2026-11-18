import BizError from '../../error/biz-error';
function canonical(value) {
 if(Array.isArray(value)) return value.map(canonical);
 if(value && typeof value==='object') return Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])]));
 return value;
}
export async function sendOnce(db, userId, key, payload, provider) {
 if(typeof key!=='string'||!/^[A-Za-z0-9_-]{10,100}$/.test(key))throw new BizError('A stable Idempotency-Key is required',400);
 const bytes=new TextEncoder().encode(JSON.stringify(canonical(payload)));
 if(bytes.length>15*1024*1024)throw new BizError('Encoded send exceeds 15 MB',413);
 const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(x=>x.toString(16).padStart(2,'0')).join('');
 await db.prepare('INSERT OR IGNORE INTO mobile_send_intent(user_id,request_key,account_id,payload_hash) VALUES(?,?,?,?)').bind(userId,key,payload.accountId,hash).run();
 const existing=await db.prepare('SELECT * FROM mobile_send_intent WHERE user_id=? AND request_key=?').bind(userId,key).first();
 if(existing.payload_hash!==hash)throw new BizError('This send key belongs to different content',409);
 const claimed=await db.prepare("UPDATE mobile_send_intent SET state='sending',updated_at=CURRENT_TIMESTAMP WHERE user_id=? AND request_key=? AND state='pending'").bind(userId,key).run();
 if(!claimed.meta.changes)return {state:existing.state,requestKey:key,result:existing.result?JSON.parse(existing.result):null};
 let state='unknown', result=null;
 try {
  const response=await provider();
  result={sentRecipients:response?.sentRecipients||[],failedRecipients:response?.failedRecipients||[]};
  state=result.sentRecipients.length?(result.failedRecipients.length?'partial':'accepted'):'rejected';
 } catch { /* Provider may have accepted. Never retry here or leak provider exceptions. */ }
 await db.prepare('UPDATE mobile_send_intent SET state=?,result=?,updated_at=CURRENT_TIMESTAMP WHERE user_id=? AND request_key=?').bind(state,result?JSON.stringify(result):null,userId,key).run();
 return {state,requestKey:key,result};
}
