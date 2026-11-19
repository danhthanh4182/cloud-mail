import {env} from 'cloudflare:workers';
import {it,expect} from 'vitest';
import base from '../../migrations/001_mobile.sql?raw';
import completion from '../../migrations/002_mobile_completion.sql?raw';
import {deleteDraft,getDrafts,putDraft} from '../../src/service/mobile/drafts';

it('D1 applies the additive migration twice and returns an atomic draft tombstone',async()=>{
 await env.db.exec('CREATE TABLE IF NOT EXISTS account(account_id INTEGER PRIMARY KEY,user_id INTEGER,is_del INTEGER);');
 await env.db.exec('CREATE TABLE IF NOT EXISTS email(email_id INTEGER PRIMARY KEY,user_id INTEGER,account_id INTEGER,message_id TEXT,in_reply_to TEXT);');
 for(const migration of [base,completion,completion]) {
  for(const statement of migration.split(';').filter(item=>item.trim())) {
   await env.db.prepare(statement).run();
  }
 }
 await env.db.prepare('INSERT INTO account VALUES(3001,300,0)').run();
 const payload={id:'worker-draft',accountId:3001,body:'before'};
 await putDraft(env.db,300,payload.id,{payload,revision:0});
 await deleteDraft(env.db,300,payload.id,1);
 await deleteDraft(env.db,300,payload.id,1);
 expect((await getDrafts(env.db,300)).list).toEqual([{
  draftId:payload.id,revision:2,payload:null,deleted:true
 }]);
});
