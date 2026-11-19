import {env} from 'cloudflare:workers';
import {expect,it} from 'vitest';
import migration from '../../migrations/003_sender_authentication.sql?raw';
import {authenticatedSenderIds,persistSenderAuthentication} from '../../src/service/mobile/sender-authentication';

it('D1 keeps repeatable boolean evidence owner scoped, with a pre-migration fallback',async()=>{
 await persistSenderAuthentication(env.db,{emailId:9001,userId:900},true);
 expect([...await authenticatedSenderIds(env.db,900,[9001])]).toEqual([]);
 await env.db.exec('CREATE TABLE IF NOT EXISTS email(email_id INTEGER PRIMARY KEY);');
 await env.db.prepare('INSERT INTO email(email_id) VALUES(9001),(9002),(9003)').run();
 for(let pass=0;pass<2;pass++) {
  for(const statement of migration.split(';').filter(sql=>sql.trim()))await env.db.prepare(statement).run();
 }
 await persistSenderAuthentication(env.db,{emailId:9001,userId:900},true);
 await persistSenderAuthentication(env.db,{emailId:9002,userId:901},true);
 await persistSenderAuthentication(env.db,{emailId:9003,userId:900},false);
 expect([...await authenticatedSenderIds(env.db,900,[9001,9002,9003])]).toEqual([9001]);
 expect(await env.db.prepare('SELECT * FROM mobile_sender_authentication WHERE email_id=9001').first())
  .toEqual({email_id:9001,user_id:900,sender_domain_authenticated:1});
 expect(await env.db.prepare('SELECT COUNT(*) AS count FROM mobile_sender_authentication').first()).toEqual({count:2});
 await env.db.prepare('DELETE FROM email WHERE email_id=9001').run();
 expect([...await authenticatedSenderIds(env.db,900,[9001])]).toEqual([]);
 expect(await env.db.prepare('SELECT COUNT(*) AS count FROM mobile_sender_authentication').first()).toEqual({count:1});
});
