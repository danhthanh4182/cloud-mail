import BizError from '../../error/biz-error';

export class MobileStore {
 constructor(db, userId) { this.db=db; this.userId=userId; }
 async state(emailId) {
  return await this.db.prepare('SELECT * FROM mobile_mail_state WHERE user_id=? AND email_id=?').bind(this.userId,Number(emailId)).first() || {email_id:Number(emailId),folder:'inbox',labels:'[]',version:0};
 }
 async mutate(emailId, patch) {
  await this.detail(emailId);
  if(!Number.isSafeInteger(patch.version) || patch.version<0) throw new BizError('Expected version is required',400);
  const before=await this.state(emailId);
  const folder=patch.folder ?? before.folder;
  if(!['inbox','archive','spam','trash'].includes(folder)) throw new BizError('Invalid folder',400);
  const labels=patch.labels ?? JSON.parse(before.labels);
  if(!Array.isArray(labels)||labels.length>20||labels.some(x=>typeof x!=='string'||x.length>80)) throw new BizError('Invalid labels',400);
  if(patch.read!==undefined && typeof patch.read!=='boolean') throw new BizError('Invalid read flag',400);
  await this.db.prepare('INSERT OR IGNORE INTO mobile_mail_state(user_id,email_id) VALUES(?,?)').bind(this.userId,Number(emailId)).run();
  const statements=[
   this.db.prepare('UPDATE mobile_mail_state SET folder=?,labels=?,version=version+1,updated_at=CURRENT_TIMESTAMP WHERE user_id=? AND email_id=? AND version=?').bind(folder,JSON.stringify(labels),this.userId,Number(emailId),patch.version),
   this.db.prepare('INSERT INTO mobile_event(user_id,email_id,version) SELECT user_id,email_id,version FROM mobile_mail_state WHERE user_id=? AND email_id=? AND changes()>0').bind(this.userId,Number(emailId))
  ];
  if(patch.read!==undefined)statements.push(this.db.prepare('UPDATE email SET unread=? WHERE email_id=? AND user_id=? AND changes()>0').bind(patch.read?1:0,Number(emailId),this.userId));
  const results=await this.db.batch(statements);
  if(!results[0].meta.changes) throw new BizError('Message changed on another device; refresh before retrying',409);
  const row=await this.state(emailId);return {...row,labels:JSON.parse(row.labels)};
 }
 async detail(emailId) {
  const row=await this.db.prepare('SELECT e.* FROM email e JOIN account a ON a.account_id=e.account_id WHERE e.email_id=? AND e.user_id=? AND a.user_id=? AND e.is_del=0 AND a.is_del=0').bind(Number(emailId),this.userId,this.userId).first();
  if(!row) throw new BizError('Mail not found',404);
  return row;
 }
}
