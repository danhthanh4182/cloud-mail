import { MobileStore } from './store';

function identifiers(value) {
 return String(value ?? '').split(/[\s<>]+/).filter(id => /^[^\s<>]{1,254}@[A-Za-z0-9.\-\[\]:]+$/.test(id));
}

export async function conversation(db, userId, emailId) {
 const anchor = await new MobileStore(db, userId).detail(emailId);
 const threads = new Map([[anchor.email_id, anchor]]);
 let frontier = [anchor];
 const inspected = new Set();
 let truncated = false;
 // Bound both SQL variables and D1 round trips when processing hostile headers.
 for (let depth = 0; depth < 10 && frontier.length; depth++) {
  const candidates = [...new Set(frontier.flatMap(row =>
   [row.message_id, row.in_reply_to, row.relation].flatMap(identifiers)).filter(id => !inspected.has(id)))];
  const keys = candidates.slice(0, 20);
  if (!keys.length) break;
  if (candidates.length > keys.length) truncated = true;
  for (const key of keys) inspected.add(key);
  const marks = keys.map(() => '?').join(',');
  const normalizedReferences = "(' ' || replace(replace(replace(replace(replace(coalesce(e.relation,''), '<',' '), '>',' '), char(9),' '),char(10),' '),char(13),' ') || ' ')";
  const references = keys.map(() => `instr(${normalizedReferences}, ' ' || ? || ' ') > 0`).join(' OR ');
  const rows = (await db.prepare(`
   SELECT e.email_id,e.account_id,e.subject,e.send_email,e.name,e.create_time,
          e.message_id,e.in_reply_to,e.relation,e.type,e.unread,
          COALESCE(s.folder,'inbox') AS folder,COALESCE(s.version,0) AS version,
          COALESCE(s.labels,'[]') AS labels,st.star_id
   FROM email e
   LEFT JOIN mobile_mail_state s ON s.user_id=e.user_id AND s.email_id=e.email_id
   LEFT JOIN star st ON st.user_id=e.user_id AND st.email_id=e.email_id
   WHERE e.user_id=? AND e.account_id=? AND e.is_del=0
     AND (trim(e.message_id,' <>') IN (${marks}) OR trim(e.in_reply_to,' <>') IN (${marks}) OR ${references})
   ORDER BY e.email_id DESC LIMIT 51
  `).bind(userId,anchor.account_id,...keys,...keys,...keys).all()).results;
  // Keep only metadata for the anchor too; the reader already loaded its body.
  frontier = [];
  for (const row of rows) {
   if (threads.has(row.email_id)) continue;
   if (threads.size >= 50) { truncated = true; break; }
   threads.set(row.email_id,row);
   frontier.push(row);
  }
  if (depth === 9 && frontier.length) truncated = true;
 }
 const list = [...threads.values()].filter(row => row.email_id !== anchor.email_id)
  .sort((a,b)=>String(a.create_time).localeCompare(String(b.create_time)) || a.email_id-b.email_id);
 return {list,truncated};
}
