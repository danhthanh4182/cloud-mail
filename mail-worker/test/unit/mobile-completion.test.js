import {readFileSync} from 'node:fs';
import {describe,expect,it,vi} from 'vitest';
import {testDb} from '../helpers/mobile-db';
import {conversation} from '../../src/service/mobile/conversation';
import {deleteDraft,getDrafts,putDraft} from '../../src/service/mobile/drafts';
import {classify,replySuggestion,reserveAiCall,saveSenderRule} from '../../src/service/mobile/smart-mail';
import {notifyIncomingMail,pushPayload,registerPush,revokePush,rotatePush} from '../../src/service/mobile/push';

function fixture() {
 const db=testDb(`
  CREATE TABLE account(account_id INTEGER PRIMARY KEY,user_id INTEGER,is_del INTEGER DEFAULT 0);
  CREATE TABLE email(email_id INTEGER PRIMARY KEY,user_id INTEGER,account_id INTEGER,subject TEXT,
   message_id TEXT,in_reply_to TEXT,relation TEXT,is_del INTEGER DEFAULT 0,create_time TEXT,
   type INTEGER DEFAULT 0,unread INTEGER DEFAULT 0,send_email TEXT,name TEXT);
  CREATE TABLE star(star_id INTEGER PRIMARY KEY,user_id INTEGER,email_id INTEGER);
  INSERT INTO account(account_id,user_id) VALUES (10,1),(11,1),(20,2);
 `);
 for(const migration of ['001_mobile.sql','002_mobile_completion.sql','002_mobile_completion.sql']) {
  db.sqlite.exec(readFileSync(new URL(`../../migrations/${migration}`,import.meta.url),'utf8'));
 }
 return db;
}

describe('mobile completion contracts',()=>{
 it('traverses exact header links within the anchor mailbox only',async()=>{
  const db=fixture();
  db.sqlite.exec(`
   INSERT INTO email(email_id,user_id,account_id,subject,message_id,in_reply_to,relation,create_time)
   VALUES (1,1,10,'Same subject','<root@example.test>','','','2026-11-17'),
   (2,1,10,'Re: Same subject','<reply@example.test>','<root@example.test>','','2026-11-18'),
   (3,1,10,'Next reply','<later@example.test>','','<root@example.test> <reply@example.test>','2026-11-19'),
   (4,1,10,'Same subject','<unrelated@example.test>','','','2026-11-19'),
   (5,1,11,'Other mailbox','<other@example.test>','<root@example.test>','','2026-11-19'),
   (6,2,20,'Foreign mailbox','<foreign@example.test>','<reply@example.test>','','2026-11-19'),
   (7,1,10,'Similar ID','<prefix-root@example.test>','','','2026-11-19');
  `);
  const result=await conversation(db,1,2);
  expect(result.list.map(row=>row.email_id)).toEqual([1,3]);
  await expect(conversation(db,1,6)).rejects.toMatchObject({code:404});
 });

 it('enforces draft revisions, ownership and tombstones without syncing device-only data',async()=>{
  const db=fixture();
  const draft={id:'draft-one',accountId:10,subject:'subject',body:'one',attachmentCount:1,
   requestKey:'local-only',attachments:[{content:'DEMO'}]};
  expect(await putDraft(db,1,draft.id,{revision:0,payload:draft})).toMatchObject({revision:1});
  await expect(putDraft(db,2,draft.id,{revision:0,payload:draft})).rejects.toMatchObject({code:404});
  await putDraft(db,1,draft.id,{revision:1,payload:{...draft,body:'two'}});
  await expect(putDraft(db,1,draft.id,{revision:1,payload:draft})).rejects.toMatchObject({code:409});
  const row=(await getDrafts(db,1)).list[0];
  expect(row.payload).toMatchObject({body:'two',attachmentCount:1});
  expect(row.payload).not.toHaveProperty('attachments');
  expect(row.payload).not.toHaveProperty('requestKey');
  expect((await getDrafts(db,2)).list).toEqual([]);
  await expect(deleteDraft(db,1,draft.id,1)).rejects.toMatchObject({code:409});
  await deleteDraft(db,1,draft.id,2);
  await deleteDraft(db,1,draft.id,2);
  expect((await getDrafts(db,1)).list).toEqual([{
   draftId:draft.id,revision:3,deleted:true,payload:null,
  }]);
  await expect(putDraft(db,1,draft.id,{revision:0,payload:draft})).rejects.toMatchObject({code:409});
 });

 it('paginates draft snapshots within the Android response budget',async()=>{
  const db=fixture();
  const body='x'.repeat(380000);
  for (let i=0;i<21;i++) {
   const payload={id:`draft-page-${String(i).padStart(2,'0')}`,accountId:10,body};
   await putDraft(db,1,payload.id,{revision:0,payload});
  }
  const page=await getDrafts(db,1);
  expect(page.list).toHaveLength(20);
  expect(Buffer.byteLength(JSON.stringify(page))).toBeLessThan(9*1024*1024);
  const next=await getDrafts(db,1,page.nextCursor);
  expect(next.list.map(draft=>draft.draftId)).toEqual(['draft-page-20']);
  expect(next.nextCursor).toBeNull();
 });

 it('prioritizes an owned sender rule and caps hosted AI calls',async()=>{
  const db=fixture();
  const mail={subject:'Your security code',send_email:'Sender@example.test'};
  expect(classify(mail)).toMatchObject({category:'security',reason:'subject'});
  await saveSenderRule(db,1,mail.send_email,'updates');
  const {results}=await db.prepare('SELECT sender,category FROM mobile_sender_rule WHERE user_id=?').bind(1).all();
  expect(classify(mail,new Map(results.map(row=>[row.sender,row.category]))))
   .toEqual({category:'updates',reason:'senderRule'});
  for(let call=0;call<20;call++) await reserveAiCall(db,1,0);
  await expect(reserveAiCall(db,1,0)).rejects.toMatchObject({code:429});
  await reserveAiCall(db,2,0);
  await reserveAiCall(db,1,3600000);
  expect(replySuggestion({response:'{"draft":"Thank you for the update."}'}).draft).toBe('Thank you for the update.');
  expect(()=>replySuggestion({response:'{"draft":"See https://example.test/reset"}'})).toThrow();
 });

 it('scopes push registration to owner and session and sends privacy-safe data only',async()=>{
  const db=fixture();
  const device='placeholder-installation-a',token='placeholder-registration-token';
  const rotationKey='test-rotation-'.repeat(4);
  await registerPush(db,1,'test session',device,token,undefined,rotationKey);
  const env={db,kv:{get:async()=>({tokens:['test session']})}};
  await expect(rotatePush(env,device,'wrong-'.repeat(8),token)).rejects.toMatchObject({code:401});
  const replacement='replacement-registration-token';
  await rotatePush(env,device,rotationKey,replacement);
  expect(await db.prepare('SELECT token FROM mobile_push_registration').first()).toEqual({token:replacement});
  await expect(registerPush(db,2,'other session',device,token)).rejects.toMatchObject({code:409});
  await revokePush(db,1,'other session',device);
  expect(await db.prepare('SELECT user_id FROM mobile_push_registration').first()).toEqual({user_id:1});
  expect(pushPayload(device,token,123).message).toMatchObject({
   data:{kind:'new_mail',device_id:device,email_id:'123'},
  });
  expect(Object.keys(pushPayload(device,token,123).message.data)).toHaveLength(3);
  expect(pushPayload(device,token,123).message).not.toHaveProperty('notification');
  const fetcher=vi.fn();
  await notifyIncomingMail({
   db,kv:{get:async()=>({tokens:['other session']})},
   MOBILE_FCM_SERVICE_ACCOUNT:JSON.stringify({project_id:'test-mail-project',client_email:'test@example.test',private_key:'demo'}),
  },1,123,fetcher);
  expect(fetcher).not.toHaveBeenCalled();
  await revokePush(db,1,'test session',device);
  expect(await db.prepare('SELECT user_id FROM mobile_push_registration').first()).toBeNull();
 });
});
