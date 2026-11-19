import BizError from '../../error/biz-error';
import { redactAssistantInput } from './assistant';

export const categories = ['primary','updates','promotions','security','invoice'];
const normalize = value => String(value ?? '').trim().toLowerCase();

export function classify(message, rules = new Map()) {
 const rule = rules.get(normalize(message.send_email));
 if (rule) return {category:rule,reason:'senderRule'};
 const subject = normalize(message.subject);
 for (const [category,pattern] of [
  ['security',/verification|security|\botp\b|mã xác nhận|bảo mật/],
  ['invoice',/invoice|receipt|hóa đơn|hoá đơn|biên lai/],
  ['promotions',/promotion|discount|\bsale\b|khuyến mãi|giảm giá/],
  ['updates',/update|newsletter|bản tin|cập nhật/],
 ]) {
  if (pattern.test(subject)) return {category,reason:'subject'};
 }
 return {category:'primary',reason:'default'};
}

export async function saveSenderRule(db,userId,sender,category) {
 sender = normalize(sender);
 if (!/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(sender) || sender.length>254 || !categories.includes(category)) {
  throw new BizError('Invalid sender or category',400);
 }
 const written = await db.prepare(`
  INSERT INTO mobile_sender_rule (user_id,sender,category)
  SELECT ?,?,? WHERE (SELECT COUNT(*) FROM mobile_sender_rule WHERE user_id=?) < 200
   OR EXISTS (SELECT 1 FROM mobile_sender_rule WHERE user_id=? AND sender=?)
  ON CONFLICT(user_id,sender) DO UPDATE SET category=excluded.category
 `).bind(userId,sender,category,userId,userId,sender).run();
 if (!written.meta.changes) throw new BizError('Sender rule limit reached',409);
 return {sender,category};
}

export async function reserveAiCall(db,userId,now=Date.now()) {
 const hour=Math.floor(now/3600000);
 const result=await db.prepare(`
  INSERT INTO mobile_ai_hour (user_id,hour,count) VALUES (?,?,1)
  ON CONFLICT(user_id) DO UPDATE SET hour=excluded.hour,
   count=CASE WHEN hour=excluded.hour THEN count+1 ELSE 1 END
  WHERE hour<excluded.hour OR (hour=excluded.hour AND count<20)
 `).bind(userId,hour).run();
 if (!result.meta.changes) throw new BizError('Assistant hourly limit reached',429);
}

export function replySuggestion(response) {
 let parsed;
 try { parsed=JSON.parse(typeof response==='string'?response:response?.response); } catch {}
 const draft=typeof parsed?.draft==='string'?parsed.draft.trim():'';
 if (!draft || draft.length>2400 || redactAssistantInput(draft)!==draft) {
  throw new BizError('Assistant did not return a usable draft',502);
 }
 return {draft};
}
