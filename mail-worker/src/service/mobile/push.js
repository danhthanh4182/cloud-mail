import BizError from '../../error/biz-error';
import KvConst from '../../const/kv-const';

const encoder=new TextEncoder();
const tokenExpiry=7*86400;
const providers=new WeakMap();

export function pushConfig(env) {
 try {
  const key=JSON.parse(env.MOBILE_FCM_SERVICE_ACCOUNT);
  if (/^[a-z][a-z0-9-]{4,62}$/.test(key.project_id) &&
      typeof key.client_email==='string' && typeof key.private_key==='string') return key;
 } catch {}
 return null;
}

const base64url=bytes=>btoa(String.fromCharCode(...bytes)).replace(/=/g,'').replace(/\+/g,'-').replace(/\//g,'_');
const hash=async text=>base64url(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(text))));
const encoded=value=>base64url(encoder.encode(JSON.stringify(value)));

export async function registerPush(db,userId,session,deviceId,token,now=Math.floor(Date.now()/1000),rotationKey) {
 if (!/^[a-zA-Z0-9_-]{20,100}$/.test(deviceId) ||
     !/^[a-zA-Z0-9:_-]{20,4096}$/.test(token) || !session) throw new BizError('Invalid push registration',400);
 if (rotationKey!=null && !/^[a-zA-Z0-9_-]{40,128}$/.test(rotationKey)) {
  throw new BizError('Invalid push rotation key',400);
 }
 const digest=await hash(session);
 const rotation=rotationKey ? await hash(rotationKey) : null;
 // Limit active registrations per owner. A token can only follow another registration of this user.
 const [,written]=await db.batch([
  db.prepare('DELETE FROM mobile_push_registration WHERE expires<=? OR (user_id=? AND token=? AND device_id<>?)')
   .bind(now,userId,token,deviceId),
  db.prepare(`
   INSERT OR IGNORE INTO mobile_push_registration (device_id,user_id,token,session_hash,rotation_hash,expires)
   SELECT ?,?,?,?,?,? WHERE (SELECT COUNT(*) FROM mobile_push_registration WHERE user_id=?) < 20
    OR EXISTS (SELECT 1 FROM mobile_push_registration WHERE device_id=? AND user_id=? AND session_hash=?)
   ON CONFLICT(device_id) DO UPDATE SET token=excluded.token,expires=excluded.expires,rotation_hash=COALESCE(excluded.rotation_hash,rotation_hash)
    WHERE user_id=excluded.user_id AND session_hash=excluded.session_hash
  `).bind(deviceId,userId,token,digest,rotation,now+tokenExpiry,userId,deviceId,userId,digest)
 ]);
 if (!written.meta.changes) throw new BizError('Push registration already in use or limit reached',409);
}

export async function revokePush(db,userId,session,deviceId) {
 if (!session) return;
 const digest=await hash(session);
 const sql='DELETE FROM mobile_push_registration WHERE user_id=? AND session_hash=?';
 if (deviceId) {
  await db.prepare(sql+' AND device_id=?').bind(userId,digest,deviceId).run();
 } else {
  await db.prepare(sql).bind(userId,digest).run();
 }
}

// This credential can only replace a token for one existing installation.
export async function rotatePush(env,deviceId,rotationKey,token,now=Math.floor(Date.now()/1000)) {
 if (!/^[a-zA-Z0-9_-]{20,100}$/.test(deviceId) ||
     !/^[a-zA-Z0-9_-]{40,128}$/.test(rotationKey) ||
     !/^[a-zA-Z0-9:_-]{20,4096}$/.test(token)) throw new BizError('Invalid push rotation',400);
 const digest=await hash(rotationKey);
 const db=env.db;
 const registration=await db.prepare(`
  SELECT user_id,session_hash FROM mobile_push_registration WHERE device_id=? AND rotation_hash=? AND expires>?
 `).bind(deviceId,digest,now).first();
 if (!registration) throw new BizError('Push registration expired',401);
 const auth=await env.kv.get(KvConst.AUTH_INFO+registration.user_id,{type:'json'});
 const active=await Promise.all((auth?.tokens || []).map(hash));
 if (!active.includes(registration.session_hash)) throw new BizError('Push session ended',401);
 const result=await db.prepare(`
  UPDATE OR IGNORE mobile_push_registration SET token=?,expires=?
  WHERE device_id=? AND rotation_hash=? AND expires>?
 `).bind(token,now+tokenExpiry,deviceId,digest,now).run();
 if (!result.meta.changes) throw new BizError('Push registration changed',409);
}

async function accessToken(env,key,fetcher) {
 const now=Math.floor(Date.now()/1000);
 const cached=providers.get(env);
 if (cached?.expires>now+60) return cached.token;
 if (cached?.pending) return cached.pending;
 const pending=(async()=>{
  const pem=key.private_key.replace(/-----[^-]+-----|\s/g,'');
  const privateKey=await crypto.subtle.importKey(
   'pkcs8',Uint8Array.from(atob(pem),ch=>ch.charCodeAt(0)),
   {name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']
  );
  const endpoint='https://oauth2.googleapis.com/token';
  const assertion=encoded({alg:'RS256',typ:'JWT'})+'.'+encoded({
   iss:key.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',
   aud:endpoint,iat:now,exp:now+3600
  });
  const signature=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',privateKey,encoder.encode(assertion));
  const response=await fetcher(endpoint,{
   method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
   body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion:assertion+'.'+base64url(new Uint8Array(signature))}),
   signal:AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new Error('Push OAuth request failed');
  const result=await response.json();
  if (!result.access_token) throw new Error('Push OAuth response invalid');
  providers.set(env,{token:result.access_token,expires:now+Number(result.expires_in||300)});
  return result.access_token;
 })();
 providers.set(env,{pending});
 try {return await pending;} catch(e) {providers.delete(env);throw e;}
}

export function pushPayload(deviceId,token,emailId) {
 return {message:{token,data:{kind:'new_mail',device_id:deviceId,email_id:String(emailId)},
  android:{priority:'high',ttl:'300s'}}};
}

export async function notifyIncomingMail(env,userId,emailId,fetcher=fetch) {
 const config=pushConfig(env);
 if (!config || !userId) return;
 const db=env.db;
 const rows=(await db.prepare(
  'SELECT device_id,token,session_hash FROM mobile_push_registration WHERE user_id=? AND expires>? LIMIT 20'
 ).bind(userId,Math.floor(Date.now()/1000)).all()).results;
 if (!rows.length) return;
 const session=await env.kv.get(KvConst.AUTH_INFO+userId,{type:'json'});
 const hashes=new Set(await Promise.all((session?.tokens || []).map(hash)));
 const active=rows.filter(row=>hashes.has(row.session_hash));
 if (!active.length) return;
 const access=await accessToken(env,config,fetcher);
 await Promise.allSettled(active.map(async row=>{
  const response=await fetcher(`https://fcm.googleapis.com/v1/projects/${config.project_id}/messages:send`,{
   method:'POST',
   headers:{Authorization:`Bearer ${access}`,'Content-Type':'application/json'},
   body:JSON.stringify(pushPayload(row.device_id,row.token,emailId)),
   signal:AbortSignal.timeout(8000),
  });
  if (response.status===404) {
   const error=await response.json();
   if (error?.error?.details?.some(detail=>detail.errorCode==='UNREGISTERED')) {
    await db.prepare('DELETE FROM mobile_push_registration WHERE device_id=? AND token=?')
     .bind(row.device_id,row.token).run();
   }
  }
 }));
}
