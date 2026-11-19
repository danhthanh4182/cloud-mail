import BizError from '../../error/biz-error';
const secrets=/(?:\b(?:password|passphrase|passwd|pwd|authorization|api[_ -]?key|access[_ -]?token|refresh[_ -]?token|secret|mật\s+khẩu)\s*[:=]\s*[^\r\n]+)|\bBearer\s+\S+|\b(?:sk|ghp|gho|github_pat|xoxb|xoxp)[_-][A-Za-z0-9_-]{12,}|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/gi;
export function redactAssistantInput(source){return String(source).replace(secrets,'[REDACTED CREDENTIAL]').replace(/https?:\/\/[^\s<>]+/gi,'[REDACTED LINK]').replace(/\b\d{3}[ -]\d{3}\b|\b\d{4,12}\b/g,'[REDACTED NUMBER]');}
export function validateAssistantOutput(parsed,source){
 secrets.lastIndex=0;
 const text=JSON.stringify(parsed);
 if(secrets.test(text)||/https?:\/\//i.test(text)||typeof parsed.summary!=='string'||parsed.summary.length>1200||!Array.isArray(parsed.evidence)||!parsed.evidence.length||parsed.evidence.some(x=>typeof x!=='string'||x.length<8||!source.includes(x)))throw new BizError('Assistant output could not be verified against the source',502);
 return {summary:parsed.summary,category:['primary','updates','promotions','security','invoice'].includes(parsed.category)?parsed.category:'primary',evidence:parsed.evidence.slice(0,3)};
}
