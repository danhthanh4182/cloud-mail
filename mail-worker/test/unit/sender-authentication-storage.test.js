import {readFileSync} from 'node:fs';
import {describe,expect,it,vi} from 'vitest';
import {testDb} from '../helpers/mobile-db';
import {authenticatedSenderIds,persistSenderAuthentication} from '../../src/service/mobile/sender-authentication';
vi.mock('../../src/security/user-context',()=>({default:{getUserId:()=>1}}));
vi.mock('../../src/service/att-service',()=>({default:{list:async()=>[]}}));
import app from '../../src/hono/hono';
import '../../src/api/mobile-api';
const sql=readFileSync(new URL('../../migrations/003_sender_authentication.sql',import.meta.url),'utf8');
function fixture(migrated=true) {
 const db=testDb(`CREATE TABLE account(account_id INTEGER PRIMARY KEY,user_id INTEGER,is_del INTEGER);
 CREATE TABLE email(email_id INTEGER PRIMARY KEY,user_id INTEGER,account_id INTEGER,type INTEGER,is_del INTEGER,subject TEXT,text TEXT,create_time TEXT,content TEXT,send_email TEXT);
 CREATE TABLE star(star_id INTEGER PRIMARY KEY,user_id INTEGER,email_id INTEGER);
 INSERT INTO account VALUES(10,1,0),(20,2,0);
 INSERT INTO email VALUES(100,1,10,0,0,'Verified','Synthetic','2026-11-19','','sender@example.test'),
 (101,1,10,0,0,'Legacy','Synthetic','2026-11-19','','sender@example.test'),
 (200,2,20,0,0,'Foreign','Synthetic','2026-11-19','','sender@example.test');`);
 db.sqlite.exec(readFileSync(new URL('../../migrations/001_mobile.sql',import.meta.url),'utf8'));
 if(migrated) {db.sqlite.exec(sql);db.sqlite.exec(sql);}
 return db;
}
describe('stored provider evidence',()=>{
 it('keeps only boolean evidence and scopes reads to its owner',async()=>{
  const db=fixture();
  await persistSenderAuthentication(db,{emailId:100,userId:1},true);
  await persistSenderAuthentication(db,{emailId:200,userId:2},true);
  await persistSenderAuthentication(db,{emailId:101,userId:1},'true');
  expect([...await authenticatedSenderIds(db,1,[100,101,200])]).toEqual([100]);
  expect(db.sqlite.prepare('SELECT * FROM mobile_sender_authentication WHERE email_id=100').get())
   .toEqual({email_id:100,user_id:1,sender_domain_authenticated:1});
  expect(()=>db.sqlite.exec('UPDATE mobile_sender_authentication SET sender_domain_authenticated=2')).toThrow();
 });
 it('exposes server evidence on owned list/detail only, never a request claim',async()=>{
  const db=fixture();
  await persistSenderAuthentication(db,{emailId:100,userId:1},true);
  await persistSenderAuthentication(db,{emailId:200,userId:2},true);
  const list=(await (await app.request('http://test/mobile/mail?senderDomainAuthenticated=true',{}, {db})).json()).data.list;
  expect(list.map(row=>[row.emailId,row.senderDomainAuthenticated])).toEqual([[101,false],[100,true]]);
  const detail=(await (await app.request('http://test/mobile/mail/100',{}, {db})).json()).data;
  expect(detail.senderDomainAuthenticated).toBe(true);
  const foreign=await (await app.request('http://test/mobile/mail/200',{}, {db})).json();
  expect(foreign.code).toBe(404);
 });
 it('retains receipt and list/detail compatibility before migration',async()=>{
  const db=fixture(false);
  await persistSenderAuthentication(db,{emailId:100,userId:1},true);
  expect([...await authenticatedSenderIds(db,1,[100])]).toEqual([]);
  for(const path of ['/mobile/mail','/mobile/mail/100']) {
   const response=await (await app.request(`http://test${path}`,{}, {db})).json();
   expect(response.code).toBe(200);
   const rows=response.data.list??[response.data];
   expect(rows.every(row=>row.senderDomainAuthenticated===false)).toBe(true);
  }
 });
});
