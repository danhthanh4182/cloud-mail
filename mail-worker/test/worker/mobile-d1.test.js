import {env} from 'cloudflare:workers';
import {it,expect} from 'vitest';
import migration from '../../migrations/001_mobile.sql?raw';
import {MobileStore} from '../../src/service/mobile/store';
it('versioned organization is atomic on the actual D1 runtime and migration is repeatable',async()=>{
 await env.db.exec('CREATE TABLE IF NOT EXISTS account(account_id INTEGER PRIMARY KEY,user_id INTEGER,is_del INTEGER DEFAULT 0);CREATE TABLE IF NOT EXISTS email(email_id INTEGER PRIMARY KEY,user_id INTEGER,account_id INTEGER,is_del INTEGER DEFAULT 0,unread INTEGER DEFAULT 0);');
 for(let pass=0;pass<2;pass++)for(const statement of migration.split(';').filter(s=>s.trim()))await env.db.prepare(statement).run();
 await env.db.prepare('INSERT INTO account(account_id,user_id) VALUES(1001,1),(2002,2)').run();await env.db.prepare('INSERT INTO email(email_id,user_id,account_id) VALUES(1001,1,1001),(2002,2,2002)').run();
 const store=new MobileStore(env.db,1);expect(await store.mutate(1001,{version:0,folder:'archive',read:true})).toMatchObject({folder:'archive',version:1});await expect(store.mutate(1001,{version:0,folder:'trash',read:false})).rejects.toMatchObject({code:409});await expect(store.detail(2002)).rejects.toMatchObject({code:404});expect((await env.db.prepare('SELECT unread FROM email WHERE email_id=1001').first()).unread).toBe(1);expect((await env.db.prepare('SELECT COUNT(*) AS count FROM mobile_event').first()).count).toBe(1);
});
