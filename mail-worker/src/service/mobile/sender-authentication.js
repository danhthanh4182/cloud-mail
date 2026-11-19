import {addressParser} from 'postal-mime';

const table='mobile_sender_authentication';

function domain(value) {
 if (typeof value!=='string' || value.length>253) return null;
 const name=value.toLowerCase();
 return name.includes('.') && name.split('.').every(label=>
  /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label)) ? name : null;
}

// Tokenize a deliberately small Authentication-Results grammar. Quoted strings
// stay opaque, comments are skipped, and commas never join separate headers.
function resultSections(value) {
 if (typeof value!=='string' || !value || value.length>8192) return null;
 value=value.replace(/\r\n[ \t]+/g,' ');
 if (/[^\x20-\x7e\t]/.test(value)) return null;
 const sections=[[]];
 for(let i=0;i<value.length;) {
  const ch=value[i];
  if (/\s/.test(ch)) {i++;continue;}
  if (ch==='(') {
   let depth=1;i++;
   while(i<value.length && depth) {
    const next=value[i++];
    if(next==='\\') {if(i===value.length)return null;i++;}
    else if(next==='(') {if(++depth>8)return null;}
    else if(next===')') depth--;
   }
   if(depth)return null;
   continue;
  }
  if (ch===';') {sections.push([]);i++;continue;}
  if (ch==='=') {sections.at(-1).push({value:ch});i++;continue;}
  if (ch===',' || ch===')' || ch==='\\') return null;
  if (ch==='"') {
   let text='',closed=false;i++;
   while(i<value.length) {
    const next=value[i++];
    if(next==='"') {closed=true;break;}
    if(next==='\\') {if(i===value.length)return null;text+=value[i++];}
    else text+=next;
   }
   if(!closed)return null;
   sections.at(-1).push({value:text,quoted:true});
   continue;
  }
  const start=i;
  while(i<value.length && !/[\s();=,"\\]/.test(value[i]))i++;
  sections.at(-1).push({value:value.slice(start,i)});
 }
 return sections;
}

function singleAddress(value) {
 if (typeof value!=='string' || value.length>4096) return null;
 // postal-mime tolerates malformed extra mailboxes as display names. Count
 // unquoted, uncommented address separators before accepting its interpretation.
 const lexical=resultSections(value);
 if(lexical?.length!==1 || lexical[0].filter(token=>!token.quoted)
  .reduce((count,token)=>count+(token.value.match(/@/g)?.length??0),0)!==1)return null;
 const addresses=addressParser(value);
 if(addresses.length!==1 || addresses[0].group) return null;
 const address=addresses[0].address;
 if(typeof address!=='string' || !/^[^\s<>@,;:]+@[^\s<>@,;:]+$/.test(address))return null;
 const senderDomain=domain(address.split('@')[1]);
 return senderDomain ? {address:address.toLowerCase(),domain:senderDomain} : null;
}

/** Only call with the direct Cloudflare Email Worker message.headers, never
 * imported MIME, webhooks or client-supplied authentication claims.
 * Cloudflare prepends its result; combined/repeated headers fail closed.
 * https://developers.cloudflare.com/email-service/api/route-emails/email-handler/#authentication-results
 */
export function senderDomainAuthenticated(headers,email) {
 try {
  const fromHeaders=(email?.headers??[]).filter(header=>header.key?.toLowerCase()==='from');
  const authHeaders=(email?.headers??[]).filter(header=>header.key?.toLowerCase()==='authentication-results');
  if(fromHeaders.length!==1 || authHeaders.length>1)return false;
  const rawFrom=singleAddress(fromHeaders[0].value);
  const directFrom=singleAddress(headers?.get('from'));
  if(!rawFrom || !directFrom || rawFrom.address!==directFrom.address ||
     email.from?.address?.toLowerCase()!==rawFrom.address)return false;
  const sections=resultSections(headers?.get('authentication-results'));
  const authority=sections?.shift();
  if(!authority || authority[0]?.quoted || authority[0]?.value.toLowerCase()!=='mx.cloudflare.net' ||
     authority.length>2 || (authority.length===2 &&
       (authority[1].quoted || !/^\d+$/.test(authority[1].value))))return false;
  let dmarc=null;
  for(const tokens of sections) {
   if(tokens.length<3 || tokens[0].quoted || tokens[1].quoted || tokens[1].value!=='=' || tokens[2].quoted ||
      !/^[a-z][a-z0-9_-]*(?:\/\d+)?$/i.test(tokens[0].value) ||
      !/^[a-z]+$/i.test(tokens[2].value) || (tokens.length-3)%3)return false;
   const properties=new Map();
   for(let i=3;i<tokens.length;i+=3) {
    const name=tokens[i].value.toLowerCase();
    if(tokens[i].quoted || !/^[a-z][a-z0-9_-]*(?:\.[a-z][a-z0-9_-]*)?$/.test(name) ||
       tokens[i+1].quoted || tokens[i+1].value!=='=' || !tokens[i+2].value ||
       (!tokens[i+2].quoted && tokens[i+2].value==='=') || properties.has(name))return false;
    properties.set(name,tokens[i+2].value);
   }
   if(tokens[0].value.toLowerCase().split('/')[0]==='dmarc') {
    if(dmarc!==null)return false;
    dmarc=tokens[2].value.toLowerCase()==='pass' &&
     (!properties.has('header.from') || domain(properties.get('header.from'))===rawFrom.domain);
   }
  }
  return dmarc===true;
 } catch {return false;}
}

function missingMigration(error) {
 return /no such table:\s*mobile_sender_authentication\b/i.test(String(error?.message)) ||
  (error?.cause && missingMigration(error.cause));
}

export async function persistSenderAuthentication(db,mail,authenticated) {
 if(authenticated!==true || !Number.isSafeInteger(mail.emailId) || mail.emailId<=0 ||
    !Number.isSafeInteger(mail.userId) || mail.userId<=0)return;
 try {
  await db.prepare(`INSERT INTO ${table}(email_id,user_id,sender_domain_authenticated)
   VALUES(?,?,?) ON CONFLICT(email_id) DO UPDATE SET user_id=excluded.user_id,
   sender_domain_authenticated=excluded.sender_domain_authenticated`)
   .bind(mail.emailId,mail.userId,1).run();
 } catch(error) {if(!missingMigration(error))throw error;}
}

export async function authenticatedSenderIds(db,userId,emailIds) {
 if(!emailIds.length)return new Set();
 try {
  const {results}=await db.prepare(`SELECT email_id FROM ${table}
   WHERE user_id=? AND sender_domain_authenticated=1 AND email_id IN (${emailIds.map(()=>'?').join(',')})`)
   .bind(userId,...emailIds).all();
  return new Set(results.map(row=>row.email_id));
 } catch(error) {if(missingMigration(error))return new Set();throw error;}
}
