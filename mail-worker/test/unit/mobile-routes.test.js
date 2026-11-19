import {it,expect,vi} from 'vitest';
import fs from 'node:fs';
import {testDb} from '../helpers/mobile-db';
vi.mock('../../src/security/user-context',()=>({default:{getUserId:()=>1}}));
import app from '../../src/hono/hono';
import '../../src/api/mobile-api';
const migration=fs.readFileSync(new URL('../../migrations/001_mobile.sql',import.meta.url),'utf8');
function fixture(){const db=testDb(`CREATE TABLE account(account_id INTEGER PRIMARY KEY,user_id INTEGER,is_del INTEGER);CREATE TABLE email(email_id INTEGER PRIMARY KEY,user_id INTEGER,account_id INTEGER,type INTEGER,is_del INTEGER,subject TEXT,text TEXT,create_time TEXT,content TEXT);CREATE TABLE star(star_id INTEGER PRIMARY KEY,user_id INTEGER,email_id INTEGER);INSERT INTO account VALUES(10,1,0),(20,2,0);INSERT INTO email VALUES(100,1,10,1,0,'Sent fixture','Body','2026-11-18','<table><tr><td>Invoice</td></tr></table>'),(200,2,20,0,0,'Private foreign','Body','2026-11-18','');`);db.sqlite.exec(migration);return db;}
it('never advertises safe send against an incomplete migration',async()=>{const db=testDb('CREATE TABLE mobile_mail_state(user_id INTEGER)');const response=await app.request('http://test/mobile/capabilities',{}, {db});expect((await response.json()).data.safeSend).toBe(false);});
it('trash includes owned sent mail and excludes foreign mail',async()=>{const db=fixture();db.sqlite.exec("INSERT INTO mobile_mail_state(user_id,email_id,folder) VALUES(1,100,'trash')");const response=await app.request('http://test/mobile/mail?folder=trash',{}, {db});expect((await response.json()).data.list.map(x=>x.emailId)).toEqual([100]);});
it('starred includes sent mail',async()=>{const db=fixture();db.sqlite.exec('INSERT INTO star VALUES(1,1,100)');const response=await app.request('http://test/mobile/mail?folder=star',{}, {db});expect((await response.json()).data.list.map(x=>x.emailId)).toEqual([100]);});
it('foreign attachment IDs disclose no object',async()=>{const db=fixture();db.sqlite.exec('CREATE TABLE attachments(att_id INTEGER,user_id INTEGER,email_id INTEGER,key TEXT,size INTEGER);INSERT INTO attachments VALUES(1,2,200,\'private-key\',1)');const response=await app.request('http://test/mobile/attachments/1',{}, {db});expect((await response.json()).code).toBe(404);});

it('filters starred address and HTML-only search before paging',async()=>{
 const db=fixture();
 db.sqlite.exec("INSERT INTO star VALUES(1,1,100); UPDATE email SET text='' WHERE email_id=100;");
 const response=await app.request('http://test/mobile/mail?folder=star&accountId=10&searchType=content&text=invoice&startDate=2026-11-18',{}, {db});
 expect((await response.json()).data.list.map(x=>x.emailId)).toEqual([100]);
 const other=await app.request('http://test/mobile/mail?folder=star&accountId=20&searchType=content&text=invoice',{}, {db});
 expect((await other.json()).data.list).toEqual([]);
});
