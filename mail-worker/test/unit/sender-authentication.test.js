import {describe,expect,it} from 'vitest';
import PostalMime from 'postal-mime';
import {senderDomainAuthenticated} from '../../src/service/mobile/sender-authentication';

async function fixture(result='mx.cloudflare.net; spf=pass; dkim=pass; dmarc=pass header.from=example.test',from='Sender <sender@example.test>',extra='') {
 const raw=`From: ${from}\r\nAuthentication-Results: ${result}\r\n${extra}Subject: Fixture\r\n\r\nSynthetic body`;
 const parsed=await PostalMime.parse(raw);
 const headers=new Headers({from,'authentication-results':result});
 return {parsed,headers};
}
async function check(result,from,extra) {
 const {headers,parsed}=await fixture(result,from,extra);
 return senderDomainAuthenticated(headers,parsed);
}
describe('direct Cloudflare sender-domain authentication',()=>{
 it('accepts provider DMARC pass, with or without its optional aligned header.from',async()=>{
  expect(await check()).toBe(true);
  expect(await check('mx.cloudflare.net; dmarc=pass')).toBe(true);
  expect(await check('MX.CLOUDFLARE.NET 1; dmarc=pass (aligned) header.from="example.test"')).toBe(true);
 });
 it.each([
  'attacker.test; dmarc=pass',
  'mx.cloudflare.net.attacker.test; dmarc=pass',
  'mx.cloudflare.net; spf=pass; dkim=pass',
  'mx.cloudflare.net; dmarc=fail; dmarc=pass',
  'mx.cloudflare.net; dmarc=pass; dmarc=fail',
  'mx.cloudflare.net; dmarc=pass header.from=other.test',
  'mx.cloudflare.net; dmarc=pass header.from=example.test header.from=other.test',
  'mx.cloudflare.net; dmarc=fail reason="ignored; dmarc=pass"',
  'mx.cloudflare.net; spf=pass (ignored; dmarc=pass)',
  'mx.cloudflare.net; reason="dmarc=pass"',
  'mx.cloudflare.net; dmarc="pass"',
  'mx.cloudflare.net; dmarc "=" pass',
  'mx.cloudflare.net; dmarc=pass header.from "=" example.test',
  'mx.cloudflare.net; dmarc=pass, mx.cloudflare.net; dmarc=pass',
  'mx.cloudflare.net; dmarc=fail, mx.cloudflare.net; dmarc=pass',
  'mx.cloudflare.net; dmarc=pass trailing-junk',
  'mx.cloudflare.net; dmarc=pass (unclosed',
  'mx.cloudflare.net; dmarc=pass reason="unclosed',
 ])('fails closed for untrusted, ambiguous or malformed result %s',async result=>{
  expect(await check(result)).toBe(false);
 });
 it('does not interpret fake authentication text inside comments or quoted properties',async()=>{
  expect(await check('mx.cloudflare.net; spf=pass (nested (dmarc=pass)); dmarc=fail')).toBe(false);
  expect(await check('mx.cloudflare.net; dmarc=pass reason="note; dmarc=fail"')).toBe(true);
 });
 it('rejects repeated raw authentication headers and duplicate or multiple From mailboxes',async()=>{
  expect(await check(undefined,undefined,'Authentication-Results: mx.cloudflare.net; dmarc=pass\r\n')).toBe(false);
  expect(await check(undefined,undefined,'From: other@other.test\r\n')).toBe(false);
  expect(await check(undefined,'a@example.test, b@example.test')).toBe(false);
  expect(await check(undefined,'a@example.test b@other.test')).toBe(false);
  expect(await check(undefined,'a@example.test <b@other.test>')).toBe(false);
  expect(await check(undefined,'Friends: a@example.test;')).toBe(false);
 });
 it('cannot infer authentication from a nickname, body or missing direct provider headers',async()=>{
  const {parsed}=await fixture();
  expect(senderDomainAuthenticated(new Headers(),parsed)).toBe(false);
  expect(senderDomainAuthenticated(new Headers({'authentication-results':'mx.cloudflare.net; dmarc=pass'}),parsed)).toBe(false);
  expect(senderDomainAuthenticated(null,parsed)).toBe(false);
 });
});
