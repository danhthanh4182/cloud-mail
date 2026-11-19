import {readFileSync} from 'node:fs';
import {describe,expect,it,vi} from 'vitest';
import {testDb} from '../helpers/mobile-db';
vi.mock('../../src/service/setting-service',()=>({default:{query:async()=>({receive:0})},normalizeBlacklist:value=>value??''}));
vi.mock('../../src/service/account-service',()=>({default:{selectByEmailIncludeDel:async()=>({accountId:10,userId:1})}}));
vi.mock('../../src/service/user-service',()=>({default:{selectByIdIncludeDel:async()=>({email:'admin@example.test'})}}));
vi.mock('../../src/service/ai-service',()=>({default:{extractCode:async()=>''}}));
vi.mock('../../src/service/mobile/push',()=>({scheduleIncomingPush:vi.fn()}));
vi.mock('../../src/service/email-service',()=>({default:{
 receive:async()=>({emailId:100,userId:1,accountId:10}),
 completeReceive:vi.fn(async()=>({emailId:100,userId:1,accountId:10})),
}}));
import {email} from '../../src/email/email';
import emailService from '../../src/service/email-service';

async function receive(db,result) {
 const from='Sender <sender@example.test>';
 const message={from:'bounce@example.test',to:'admin@example.test',
  headers:new Headers({from,'authentication-results':result}),
  raw:new Blob([`From: ${from}\r\nTo: admin@example.test\r\nAuthentication-Results: ${result}\r\nSubject: Synthetic\r\n\r\nFixture`]).stream(),
  setReject:vi.fn()};
 await email(message,{db,admin:'admin@example.test'},{});
 expect(message.setReject).not.toHaveBeenCalled();
}
describe('actual direct Email Worker ingest hook',()=>{
 it('persists provider evidence after receiving, with no raw header storage',async()=>{
  const db=testDb('CREATE TABLE email(email_id INTEGER PRIMARY KEY); INSERT INTO email VALUES(100);');
  db.sqlite.exec(readFileSync(new URL('../../migrations/003_sender_authentication.sql',import.meta.url),'utf8'));
  await receive(db,'mx.cloudflare.net; dmarc=fail reason="dmarc=pass"');
  expect(db.sqlite.prepare('SELECT COUNT(*) AS count FROM mobile_sender_authentication').get().count).toBe(0);
  await receive(db,'mx.cloudflare.net; dmarc=pass header.from=example.test');
  expect(db.sqlite.prepare('SELECT * FROM mobile_sender_authentication').get()).toEqual({email_id:100,user_id:1,sender_domain_authenticated:1});
 });
 it('still completes receipt on old databases without the optional migration',async()=>{
  const db=testDb('');
  await receive(db,'mx.cloudflare.net; dmarc=pass');
  expect(emailService.completeReceive).toHaveBeenCalled();
 });
});
