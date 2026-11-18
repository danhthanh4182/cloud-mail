import {describe,it,expect} from 'vitest';
import fs from 'node:fs';
const migration=fs.readFileSync(new URL('../../migrations/001_mobile.sql',import.meta.url),'utf8');
import {MobileStore} from '../../src/service/mobile/store.js';
import {testDb} from '../helpers/mobile-db.js';
function fixture(){const db=testDb(`CREATE TABLE account(account_id INTEGER PRIMARY KEY,user_id INTEGER,is_del INTEGER DEFAULT 0);CREATE TABLE email(email_id INTEGER PRIMARY KEY,user_id INTEGER,account_id INTEGER,is_del INTEGER DEFAULT 0,unread INTEGER DEFAULT 0); INSERT INTO account VALUES(10,1,0),(20,2,0); INSERT INTO email VALUES(100,1,10,0,0),(200,2,20,0,0);`);db.sqlite.exec(migration);return db;}
describe('owned mobile state',()=>{
 it('applies versioned organization and prevents lost updates',async()=>{const store=new MobileStore(fixture(),1);expect(await store.mutate(100,{version:0,folder:'archive'})).toMatchObject({folder:'archive',version:1});await expect(store.mutate(100,{version:0,folder:'trash'})).rejects.toMatchObject({code:409});});
 it('rejects a foreign message before returning metadata',async()=>{const db=fixture();await expect(new MobileStore(db,1).detail(200)).rejects.toMatchObject({code:404});});
});
