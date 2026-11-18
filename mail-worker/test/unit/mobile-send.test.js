import {it,expect} from 'vitest';
import fs from 'node:fs';
import {testDb} from '../helpers/mobile-db.js';
import {sendOnce} from '../../src/service/mobile/send.js';
function fixture(){return testDb(fs.readFileSync(new URL('../../migrations/001_mobile.sql',import.meta.url),'utf8'));}
it('does not resubmit a send after an uncertain provider failure',async()=>{const db=fixture();let calls=0;const provider=async()=>{calls++;throw Error('connection lost after acceptance');};const input={accountId:10,subject:'A',receiveEmail:['a@example.com'],text:'hello'};const first=await sendOnce(db,1,'request-123456',input,provider);const again=await sendOnce(db,1,'request-123456',input,provider);expect(first.state).toBe('unknown');expect(again.state).toBe('unknown');expect(calls).toBe(1);});
it('rejects reuse of a key with altered content',async()=>{const db=fixture();await sendOnce(db,1,'request-123456',{accountId:10,text:'first'},async()=>({sentRecipients:['a@example.com']}));await expect(sendOnce(db,1,'request-123456',{accountId:10,text:'changed'},async()=>({}))).rejects.toMatchObject({code:409});});
it('recognizes the actual together-mode emailService array result as accepted',async()=>{const db=fixture();const result=await sendOnce(db,1,'request-real-shape',{accountId:10,receiveEmail:['a@example.com']},async()=>[{emailId:123,recipient:'[{"address":"a@example.com"}]'}]);expect(result.state).toBe('accepted');expect(result.result.sentRecipients).toEqual(['a@example.com']);});
