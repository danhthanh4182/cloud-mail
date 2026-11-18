/** Return only one source-backed, contextual verification-code candidate. */
export function extractVerificationCode(subject = '', body = '') {
 const text = `${subject}\n${body}`.slice(0, 24000);
 const context = /(?:verification|security|one[- ]time|otp|mã\s+(?:xác\s+(?:nhận|minh)|bảo\s+mật)|验证码|code)[^\n\d]{0,50}?\b(\d{3} \d{3}|[A-Z]*\d[A-Z0-9]*)\b/gi;
 const candidates = new Set();
 for (const match of text.matchAll(context)) {
  const code = match[1].replace(/ /g, '');
  if (/\d/.test(code) && code.length >= 4 && code.length <= 12) candidates.add(code);
 }
 return candidates.size === 1 ? [...candidates][0] : '';
}
