import { describe, it, expect, vi, beforeEach } from 'vitest';
import { createHmac } from 'node:crypto';
import resendService from '../../src/service/resend-service';
import app from '../../src/hono/hono';
import '../../src/api/resend-api';

const SECRET = 'whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw';
const KNOWN_ID = 'msg_p5jXN8AQM9LWM0D4loKWxJek';
const KNOWN_TS = '1614265330';
const KNOWN_BODY = '{"test": 2432232314}';
const KNOWN_SIG = 'v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=';

function fakeVerifyContext({ secret = SECRET, id = KNOWN_ID, ts = KNOWN_TS, sig = KNOWN_SIG } = {}) {
	const headers = { 'svix-id': id, 'svix-timestamp': ts, 'svix-signature': sig };
	return {
		req: { header: (name) => headers[name.toLowerCase()] ?? null },
		env: { resend_webhook_secret: secret },
	};
}

function signHeaders(rawBody, ts = String(Math.floor(Date.now() / 1000)), id = 'msg_test123') {
	const key = Buffer.from(SECRET.slice('whsec_'.length), 'base64');
	const mac = createHmac('sha256', key).update(`${id}.${ts}.${rawBody}`).digest('base64');
	return { 'svix-id': id, 'svix-timestamp': ts, 'svix-signature': `v1,${mac}` };
}

describe('resend webhook verification', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
	});

	it('accepts the known Svix test vector', async () => {
		const c = fakeVerifyContext();
		await expect(resendService.verifyWebhookSignature(c, KNOWN_BODY, 1614265330)).resolves.toBe(true);
	});

	it('rejects wrong signatures, skewed timestamps and missing headers', async () => {
		const c = fakeVerifyContext({ sig: 'v1,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' });
		await expect(resendService.verifyWebhookSignature(c, KNOWN_BODY, 1614265330)).resolves.toBe(false);

		const skewed = fakeVerifyContext();
		await expect(resendService.verifyWebhookSignature(skewed, KNOWN_BODY, 1614265330 + 670)).resolves.toBe(
			false
		);

		for (const missing of ['svix-id', 'svix-timestamp', 'svix-signature']) {
			const headers = { 'svix-id': KNOWN_ID, 'svix-timestamp': KNOWN_TS, 'svix-signature': KNOWN_SIG };
			delete headers[missing];
			const ctx = {
				req: { header: (name) => headers[name.toLowerCase()] ?? null },
				env: { resend_webhook_secret: SECRET },
			};
			await expect(resendService.verifyWebhookSignature(ctx, KNOWN_BODY, 1614265330)).resolves.toBe(false);
		}
	});

	it('returns 401 unauthorized when verification fails', async () => {
		const bad = signHeaders(KNOWN_BODY);
		bad['svix-signature'] = 'v1,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
		const res = await app.request(
			'/webhooks',
			{ method: 'POST', headers: { 'content-type': 'application/json', ...bad }, body: KNOWN_BODY },
			{ resend_webhook_secret: SECRET }
		);
		expect(res.status).toBe(401);
		expect(await res.text()).toBe('unauthorized');
	});

	it('returns 400 for malformed JSON or missing email_id', async () => {
		const rawBad = 'not json';
		const resBad = await app.request(
			'/webhooks',
			{ method: 'POST', headers: { 'content-type': 'application/json', ...signHeaders(rawBad) }, body: rawBad },
			{ resend_webhook_secret: SECRET }
		);
		expect(resBad.status).toBe(400);
		expect(await resBad.text()).toBe('bad request');

		const rawNoId = JSON.stringify({ data: {} });
		const resNoId = await app.request(
			'/webhooks',
			{ method: 'POST', headers: { 'content-type': 'application/json', ...signHeaders(rawNoId) }, body: rawNoId },
			{ resend_webhook_secret: SECRET }
		);
		expect(resNoId.status).toBe(400);
		expect(await resNoId.text()).toBe('bad request');
	});

	it('keeps old behavior and warns once when no secret is set', async () => {
		const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
		const webhooks = vi.spyOn(resendService, 'webhooks').mockResolvedValue(undefined);
		const body = JSON.stringify({ data: { email_id: 'abc' }, type: 'email.delivered' });

		for (let i = 0; i < 2; i++) {
			const res = await app.request(
				'/webhooks',
				{ method: 'POST', headers: { 'content-type': 'application/json' }, body },
				{}
			);
			expect(res.status).toBe(200);
			expect(await res.text()).toBe('success');
		}
		expect(webhooks).toHaveBeenCalledTimes(2);
		expect(webhooks.mock.calls[0][1]).toEqual(JSON.parse(body));
		expect(warn).toHaveBeenCalledTimes(1);
	});

	it('returns 500 error without leaking internals when webhooks throws', async () => {
		vi.spyOn(resendService, 'webhooks').mockRejectedValue(new Error('db down'));
		const body = JSON.stringify({ data: { email_id: 'abc' }, type: 'email.delivered' });
		const res = await app.request(
			'/webhooks',
			{ method: 'POST', headers: { 'content-type': 'application/json', ...signHeaders(body) }, body },
			{ resend_webhook_secret: SECRET }
		);
		expect(res.status).toBe(500);
		const text = await res.text();
		expect(text).toBe('error');
		expect(text).not.toContain('db down');
	});
});
