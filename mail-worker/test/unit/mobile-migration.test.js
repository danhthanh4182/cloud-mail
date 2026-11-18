import {it,expect} from 'vitest';
import fs from 'node:fs';
import {testDb} from '../helpers/mobile-db.js';
it('additive migration is repeatable and leaves legacy records intact',()=>{const db=testDb('CREATE TABLE email(email_id INTEGER PRIMARY KEY, subject TEXT); INSERT INTO email VALUES(1,\'Existing\');');const sql=fs.readFileSync(new URL('../../migrations/001_mobile.sql',import.meta.url),'utf8');db.sqlite.exec(sql);db.sqlite.exec(sql);expect(db.sqlite.prepare('SELECT subject FROM email WHERE email_id=1').get().subject).toBe('Existing');});
