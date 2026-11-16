import { describe, it, expect, vi, beforeEach } from 'vitest';
import app from '../../src/hono/hono';
import { dbInit } from '../../src/init/init';
import '../../src/api/init-api';

describe('init secret', () => {
	beforeEach(() => {
		vi.restoreAllMocks();
		vi.spyOn(dbInit, 'init').mockImplementation((c) => c.text('success'));
	});

	it('accepts POST /init with a matching X-Init-Secret header', async () => {
		const res = await app.request(
			'/init',
			{ method: 'POST', headers: { 'X-Init-Secret': 's3cret' } },
			{ jwt_secret: 's3cret' }
		);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe('success');
	});

	it('rejects POST /init with a wrong header', async () => {
		const res = await app.request(
			'/init',
			{ method: 'POST', headers: { 'X-Init-Secret': 'nope' } },
			{ jwt_secret: 's3cret' }
		);
		expect(res.status).toBe(401);
	});

	it('prefers init_secret over jwt_secret when set', async () => {
		const ok = await app.request(
			'/init',
			{ method: 'POST', headers: { 'X-Init-Secret': 'other' } },
			{ init_secret: 'other', jwt_secret: 's3cret' }
		);
		expect(await ok.text()).toBe('success');

		const bad = await app.request(
			'/init',
			{ method: 'POST', headers: { 'X-Init-Secret': 's3cret' } },
			{ init_secret: 'other', jwt_secret: 's3cret' }
		);
		expect(bad.status).toBe(401);
	});

	it('keeps the deprecated GET path but warns without leaking the secret', async () => {
		const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
		const res = await app.request('/init/s3cret', { method: 'GET' }, { jwt_secret: 's3cret' });
		expect(await res.text()).toBe('success');
		expect(warn).toHaveBeenCalledTimes(1);
		expect(warn.mock.calls[0].join(' ')).not.toContain('s3cret');
	});
});
